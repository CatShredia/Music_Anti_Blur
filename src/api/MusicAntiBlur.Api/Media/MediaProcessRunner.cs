using System.Diagnostics;

namespace MusicAntiBlur.Api.Media;

public sealed class MediaProcessRunner
{
    public async Task<ProcessResult> RunAsync(string fileName, IReadOnlyList<string> args, TimeSpan timeout, CancellationToken ct)
    {
        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        foreach (var arg in args)
        {
            psi.ArgumentList.Add(arg);
        }

        Process process;
        try
        {
            process = Process.Start(psi) ?? throw new InvalidOperationException("failed to start process");
        }
        catch (Exception ex) when (ex is FileNotFoundException or System.ComponentModel.Win32Exception)
        {
            throw new FfmpegNotFoundException(fileName);
        }

        using (process)
        {
            var stdoutTask = process.StandardOutput.ReadToEndAsync(ct);
            var stderrTask = process.StandardError.ReadToEndAsync(ct);
            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(timeout);
            try
            {
                await process.WaitForExitAsync(timeoutCts.Token);
            }
            catch (OperationCanceledException) when (!ct.IsCancellationRequested)
            {
                TryKill(process);
                throw new TimeoutException($"{Path.GetFileName(fileName)} timed out.");
            }

            var stdout = await stdoutTask;
            var stderr = await stderrTask;
            if (stdout.Length > 64_000)
            {
                stdout = stdout[..64_000];
            }

            if (stderr.Length > 64_000)
            {
                stderr = stderr[..64_000];
            }

            return new ProcessResult(process.ExitCode, stdout, stderr);
        }
    }

    private static void TryKill(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch
        {
        }
    }
}

public sealed record ProcessResult(int ExitCode, string Stdout, string Stderr);

public sealed class FfmpegNotFoundException(string path) : Exception($"ffmpeg not found: {path}");
