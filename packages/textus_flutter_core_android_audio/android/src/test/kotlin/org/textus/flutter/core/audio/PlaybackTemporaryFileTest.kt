package org.textus.flutter.core.audio

import java.io.File
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class PlaybackTemporaryFileTest {
    @Rule @JvmField
    val temporaryFolder = TemporaryFolder()

    @Test
    fun normalWriteAndRepeatedCleanupPreserveUnrelatedBytes() = runBlocking {
        // Given a test-owned directory, unrelated sentinel and exact WAV bytes.
        val directory = temporaryFolder.newFolder()
        val sentinelBytes = byteArrayOf(7, 8, 9)
        val sentinel = File(directory, "unrelated.bin").apply { writeBytes(sentinelBytes) }
        val bytes = byteArrayOf(82, 73, 70, 70, 1, 2, 3)
        val owner = PlaybackTemporaryFile(directory)
        // When the actual owner writes the caller's bytes.
        val file = owner.write(bytes)
        // Then the returned file contains the exact caller bytes before cleanup.
        assertArrayEquals(bytes, file.readBytes())
        // When cleanup is repeated after successful deletion.
        owner.cleanup()
        owner.cleanup()
        // Then only the owned WAV is removed and unrelated bytes survive.
        assertFalse(file.exists())
        assertArrayEquals(sentinelBytes, sentinel.readBytes())
        assertEquals(listOf(sentinel), directory.listFiles()!!.toList())
    }

    @Test
    fun cleanupWaitsForPublishedFileWriteBeforeDeleting() = runBlocking {
        // Given a real file publication gated immediately before writing bytes.
        val directory = temporaryFolder.newFolder()
        val sentinelBytes = byteArrayOf(4, 5, 6)
        val sentinel = File(directory, "unrelated.bin").apply { writeBytes(sentinelBytes) }
        val published = AtomicReference<File>()
        val writeEntered = CountDownLatch(1)
        val releaseWrite = CountDownLatch(1)
        val cleanupEntered = CountDownLatch(1)
        val bytes = byteArrayOf(11, 12, 13)
        val owner = PlaybackTemporaryFile(
            directory,
            beforeWrite = { file ->
                published.set(file)
                writeEntered.countDown()
                assertTrue("Writer gate must be released", releaseWrite.await(5, TimeUnit.SECONDS))
            },
            beforeCleanup = { cleanupEntered.countDown() },
        )
        val writer = async(Dispatchers.IO) { owner.write(bytes) }
        var cleanup: Deferred<Unit>? = null
        try {
            assertTrue("Writer must publish its path", writeEntered.await(5, TimeUnit.SECONDS))
            // When explicit cleanup reaches its actual hook while the writer holds ownership.
            val cleaning = async(Dispatchers.IO) { owner.cleanup() }
            cleanup = cleaning
            assertTrue("Cleanup must enter", cleanupEntered.await(5, TimeUnit.SECONDS))
            // Then cleanup stays pending and the published path still exists.
            assertFalse(cleaning.isCompleted)
            assertTrue(published.get().exists())
            assertEquals(0L, published.get().length())
            // When the writer is released and both operations finish.
            releaseWrite.countDown()
            val file = withTimeout(5000) {
                val written = writer.await()
                cleaning.await()
                written
            }
            // Then completed writing cannot recreate the cleaned WAV or alter the sentinel.
            assertSame(published.get(), file)
            assertFalse(file.exists())
            assertArrayEquals(sentinelBytes, sentinel.readBytes())
            assertEquals(listOf(sentinel), directory.listFiles()!!.toList())
        } finally {
            releaseWrite.countDown()
            withContext(NonCancellable) {
                withTimeout(5000) {
                    writer.join()
                    cleanup?.join()
                    owner.cleanup()
                }
            }
        }
    }

    @Test
    fun cancelledPublishedWriterAndExplicitCleanupCannotRecreateWave() = runBlocking {
        // Given a writer gated after publication and cancellation cleanup in its finally.
        val directory = temporaryFolder.newFolder()
        val sentinelBytes = byteArrayOf(21, 22, 23)
        val sentinel = File(directory, "unrelated.bin").apply { writeBytes(sentinelBytes) }
        val published = AtomicReference<File>()
        val writeEntered = CountDownLatch(1)
        val releaseWrite = CountDownLatch(1)
        val cleanupEntered = CountDownLatch(1)
        val cancellationObserved = CompletableDeferred<Unit>()
        val owner = PlaybackTemporaryFile(
            directory,
            beforeWrite = { file ->
                published.set(file)
                writeEntered.countDown()
                assertTrue("Writer gate must be released", releaseWrite.await(5, TimeUnit.SECONDS))
            },
            beforeCleanup = { cleanupEntered.countDown() },
        )
        val writer = launch(Dispatchers.Default) {
            try {
                owner.write(byteArrayOf(31, 32, 33))
            } catch (error: CancellationException) {
                cancellationObserved.complete(Unit)
                throw error
            } finally {
                owner.cleanup()
            }
        }
        var cleanup: Deferred<Unit>? = null
        try {
            assertTrue("Writer must publish its path", writeEntered.await(5, TimeUnit.SECONDS))
            // When the published writer is cancelled and explicit cleanup starts before release.
            writer.cancel()
            val cleaning = async(Dispatchers.IO) { owner.cleanup() }
            cleanup = cleaning
            assertTrue("Cleanup must enter", cleanupEntered.await(5, TimeUnit.SECONDS))
            // Then cleanup is pending and cannot delete ahead of the blocked writer.
            assertFalse(cleaning.isCompleted)
            assertTrue(published.get().exists())
            assertEquals(0L, published.get().length())
            // When synchronous writing finishes and both cleanup paths are awaited.
            releaseWrite.countDown()
            withTimeout(5000) {
                writer.join()
                cleaning.await()
                cancellationObserved.await()
            }
            // Then cancellation remains observable without an orphan or recreated WAV.
            assertTrue(writer.isCancelled)
            assertTrue(cancellationObserved.isCompleted)
            assertFalse(published.get().exists())
            assertArrayEquals(sentinelBytes, sentinel.readBytes())
            assertEquals(listOf(sentinel), directory.listFiles()!!.toList())
        } finally {
            releaseWrite.countDown()
            withContext(NonCancellable) {
                withTimeout(5000) {
                    writer.join()
                    cleanup?.join()
                    owner.cleanup()
                }
            }
        }
    }

    @Test
    fun failedWriteRetainsPublishedPathUntilCleanup() = runBlocking {
        // Given an actual published path and an injected IOException before writing.
        val directory = temporaryFolder.newFolder()
        val sentinelBytes = byteArrayOf(41, 42, 43)
        val sentinel = File(directory, "unrelated.bin").apply { writeBytes(sentinelBytes) }
        val published = AtomicReference<File>()
        val failure = IOException("write unavailable")
        val owner = PlaybackTemporaryFile(directory, beforeWrite = { file ->
            published.set(file)
            throw failure
        })
        // When the real owner's write fails after file publication.
        val result = runCatching { owner.write(byteArrayOf(51, 52, 53)) }
        // Then coroutine recovery may copy the wrapper but preserves the exact original cause, and ownership retains the path.
        val observed = result.exceptionOrNull()
        assertTrue(observed is IOException)
        assertEquals(failure.message, observed?.message)
        assertSame(failure, if (observed === failure) observed else observed?.cause)
        assertTrue(published.get().exists())
        assertEquals(0L, published.get().length())
        // When cleanup follows the failed write.
        owner.cleanup()
        // Then the published WAV is removed while unrelated bytes survive.
        assertFalse(published.get().exists())
        assertArrayEquals(sentinelBytes, sentinel.readBytes())
        assertEquals(listOf(sentinel), directory.listFiles()!!.toList())
    }

    @Test
    fun failedDeletionRetainsExactPathForSuccessfulRetry() = runBlocking {
        // Given an owned WAV and a deletion seam which fails exactly once.
        val directory = temporaryFolder.newFolder()
        val sentinelBytes = byteArrayOf(61, 62, 63)
        val sentinel = File(directory, "unrelated.bin").apply { writeBytes(sentinelBytes) }
        val deletedPaths = mutableListOf<File>()
        val calls = AtomicInteger()
        val owner = PlaybackTemporaryFile(directory, deleteFile = { file ->
            deletedPaths.add(file)
            if (calls.incrementAndGet() == 1) false else file.delete()
        })
        val bytes = byteArrayOf(71, 72, 73)
        val file = owner.write(bytes)
        // When the first cleanup attempts deletion and receives false.
        val first = runCatching { owner.cleanup() }
        // Then cleanup reports IOException and retains the exact file and bytes for retry.
        assertTrue(first.exceptionOrNull() is IOException)
        assertEquals("Could not delete owned temporary WAV", first.exceptionOrNull()?.message)
        assertTrue(file.exists())
        assertArrayEquals(bytes, file.readBytes())
        assertEquals(1, calls.get())
        // When a second cleanup retries deletion of that same owned path.
        owner.cleanup()
        // Then exactly two deletion calls remove the WAV without touching the sentinel.
        assertEquals(2, calls.get())
        assertEquals(listOf(file, file), deletedPaths)
        assertFalse(file.exists())
        assertArrayEquals(sentinelBytes, sentinel.readBytes())
        assertEquals(listOf(sentinel), directory.listFiles()!!.toList())
    }

    @Test
    fun cleanupBeforeNewWriteClosesOwnerWithoutCreatingWave() = runBlocking {
        // Given an unused owner and unrelated bytes in its test-owned directory.
        val directory = temporaryFolder.newFolder()
        val sentinelBytes = byteArrayOf(81, 82, 83)
        val sentinel = File(directory, "unrelated.bin").apply { writeBytes(sentinelBytes) }
        val owner = PlaybackTemporaryFile(directory)
        // When cleanup closes the owner before a new write is requested.
        owner.cleanup()
        val result = runCatching { owner.write(byteArrayOf(91, 92, 93)) }
        // Then writing rejects with no WAV creation and preserves unrelated bytes.
        assertTrue(result.exceptionOrNull() is IllegalStateException)
        assertArrayEquals(sentinelBytes, sentinel.readBytes())
        assertEquals(listOf(sentinel), directory.listFiles()!!.toList())
    }
}
