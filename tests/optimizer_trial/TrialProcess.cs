using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;

namespace PZTrial
{
    public sealed class LogPipeStatus
    {
        public long BytesRead, BytesWritten, DroppedBytes, PendingBytes;
        public bool InputClosed, WriterClosed;
        public string Error;
    }

    // The pipe reader never calls a file API or waits for the writer. Overflow
    // is an explicit capture failure, not backpressure on the game thread.
    public sealed class BufferedLogPipe
    {
        private readonly object gate = new object();
        private readonly Queue<byte[]> queue = new Queue<byte[]>();
        private readonly Stream input, output;
        private readonly int capacity;
        private readonly Thread reader, writer;
        private long readBytes, writtenBytes, droppedBytes, pendingBytes;
        private bool inputClosed, writerClosed, writerFailed;
        private string error = "";

        public BufferedLogPipe(Stream input, Stream output, int capacityBytes)
        {
            if (input == null || output == null) throw new ArgumentNullException();
            if (capacityBytes < 16384) throw new ArgumentOutOfRangeException("capacityBytes");
            this.input = input;
            this.output = output;
            capacity = capacityBytes;
            reader = new Thread(ReadLoop) { IsBackground = true, Name = "PZ trial output reader" };
            writer = new Thread(WriteLoop) { IsBackground = true, Name = "PZ trial log writer" };
            writer.Start();
            reader.Start();
        }

        private void Fail(string message)
        {
            // Called only with gate held. Keep the first failure, including its source.
            if (error.Length == 0) error = message;
        }

        private void ReadLoop()
        {
            try
            {
                byte[] buffer = new byte[16384];
                int count;
                while ((count = input.Read(buffer, 0, buffer.Length)) != 0)
                {
                    lock (gate)
                    {
                        readBytes += count;
                        if (writerFailed || pendingBytes + count > capacity)
                        {
                            droppedBytes += count;
                            if (!writerFailed) Fail("Log queue capacity exceeded; output was discarded while keeping the game pipe drained.");
                            continue;
                        }
                        byte[] block = new byte[count];
                        Buffer.BlockCopy(buffer, 0, block, 0, count);
                        queue.Enqueue(block);
                        pendingBytes += count; // Includes the block currently being written.
                        Monitor.PulseAll(gate);
                    }
                }
            }
            catch (Exception ex) { lock (gate) { Fail("Pipe read failed: " + ex.Message); } }
            finally
            {
                try { input.Dispose(); }
                catch (Exception ex) { lock (gate) { Fail("Pipe close failed: " + ex.Message); } }
                lock (gate) { inputClosed = true; Monitor.PulseAll(gate); }
            }
        }

        private void WriteLoop()
        {
            try
            {
                while (true)
                {
                    byte[] block = null;
                    bool ended;
                    lock (gate)
                    {
                        if (queue.Count == 0 && !inputClosed) Monitor.Wait(gate, 250);
                        if (queue.Count != 0) block = queue.Dequeue();
                        ended = inputClosed && block == null;
                    }
                    // Disk operations must remain outside gate and outside ReadLoop.
                    if (block != null)
                    {
                        output.Write(block, 0, block.Length);
                        lock (gate) { writtenBytes += block.Length; pendingBytes -= block.Length; }
                    }
                    else
                    {
                        output.Flush();
                        if (ended) break;
                    }
                }
            }
            catch (Exception ex)
            {
                lock (gate)
                {
                    Fail("Log write failed: " + ex.Message);
                    writerFailed = true;
                    // A partially failed write is not counted as confirmed delivery.
                    droppedBytes += pendingBytes;
                    pendingBytes = 0;
                    queue.Clear();
                }
            }
            finally
            {
                try { output.Dispose(); }
                catch (Exception ex) { lock (gate) { Fail("Log close failed: " + ex.Message); writerFailed = true; } }
                lock (gate) { writerClosed = true; }
            }
        }

        public LogPipeStatus Snapshot()
        {
            lock (gate)
            {
                return new LogPipeStatus { BytesRead = readBytes, BytesWritten = writtenBytes,
                    DroppedBytes = droppedBytes, PendingBytes = pendingBytes,
                    InputClosed = inputClosed, WriterClosed = writerClosed, Error = error };
            }
        }

        public bool Wait(int milliseconds)
        {
            if (milliseconds < 0) throw new ArgumentOutOfRangeException("milliseconds");
            Stopwatch timer = Stopwatch.StartNew();
            if (!reader.Join(milliseconds)) return false;
            return writer.Join(Math.Max(0, milliseconds - (int)timer.ElapsedMilliseconds));
        }
    }

    public sealed class ProcessLogStatus
    {
        public string Policy = "AsyncPipeQueueV1";
        public string Status;
        public int QueueCapacityBytesPerStream;
        public bool CompletionTimedOut;
        public LogPipeStatus Stdout, Stderr;
    }

    public sealed class TrialProcessCapture
    {
        public Process Process { get; private set; }
        private BufferedLogPipe stdout, stderr;
        private int capacity;
        private bool timedOut;

        public static TrialProcessCapture Start(string executable, string workingDirectory,
            string arguments, string stdoutPath, string stderrPath, int capacityBytes)
        {
            if (capacityBytes < 16384) throw new ArgumentOutOfRangeException("capacityBytes");
            FileStream outFile = null, errFile = null;
            Process process = new Process();
            bool started = false;
            try
            {
                // CreateNew prevents an accidental overwrite; the launcher owns a fresh run directory.
                outFile = new FileStream(stdoutPath, FileMode.CreateNew, FileAccess.Write, FileShare.Read, 65536);
                errFile = new FileStream(stderrPath, FileMode.CreateNew, FileAccess.Write, FileShare.Read, 65536);
                process.StartInfo = new ProcessStartInfo { FileName = executable,
                    WorkingDirectory = workingDirectory, Arguments = arguments, UseShellExecute = false,
                    RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
                if (!process.Start()) throw new IOException("Could not start the trial game process.");
                started = true;
                TrialProcessCapture capture = new TrialProcessCapture { Process = process, capacity = capacityBytes };
                capture.stdout = new BufferedLogPipe(process.StandardOutput.BaseStream, outFile, capacityBytes);
                outFile = null;
                capture.stderr = new BufferedLogPipe(process.StandardError.BaseStream, errFile, capacityBytes);
                errFile = null;
                return capture;
            }
            catch
            {
                // Only a child just created by this unsuccessful start can be terminated here.
                if (started) { try { if (!process.HasExited) process.Kill(); } catch { } }
                if (outFile != null) outFile.Dispose();
                if (errFile != null) errFile.Dispose();
                process.Dispose();
                throw;
            }
        }

        private static bool Failed(LogPipeStatus status)
        {
            return status.Error.Length != 0 || status.DroppedBytes != 0;
        }

        public ProcessLogStatus Snapshot()
        {
            LogPipeStatus a = stdout.Snapshot(), b = stderr.Snapshot();
            bool closed = a.InputClosed && a.WriterClosed && b.InputClosed && b.WriterClosed;
            bool failed = timedOut || Failed(a) || Failed(b) ||
                (closed && (a.BytesRead != a.BytesWritten || b.BytesRead != b.BytesWritten));
            return new ProcessLogStatus { Status = failed ? "Incomplete" : closed ? "Complete" : "Running",
                QueueCapacityBytesPerStream = capacity, CompletionTimedOut = timedOut, Stdout = a, Stderr = b };
        }

        public ProcessLogStatus Complete(int milliseconds)
        {
            if (!Process.HasExited) throw new InvalidOperationException("Exit the game before finalizing its logs.");
            if (milliseconds < 0) throw new ArgumentOutOfRangeException("milliseconds");
            Stopwatch timer = Stopwatch.StartNew();
            bool a = stdout.Wait(milliseconds);
            bool b = stderr.Wait(Math.Max(0, milliseconds - (int)timer.ElapsedMilliseconds));
            if (!a || !b) timedOut = true;
            return Snapshot();
        }
    }
}
