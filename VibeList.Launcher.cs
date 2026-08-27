using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("Vibe List")]
[assembly: AssemblyDescription("A cozy todo checklist for Windows")]
[assembly: AssemblyCompany("Shin Daehun")]
[assembly: AssemblyProduct("Vibe List")]
[assembly: AssemblyVersion("1.2.1.0")]
[assembly: AssemblyFileVersion("1.2.1.0")]

internal static class VibeListLauncher
{
    [STAThread]
    private static int Main(string[] args)
    {
        string appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string runtimeDirectory = Path.Combine(appData, "VibeList");
        string scriptPath = Path.Combine(runtimeDirectory, "VibeList.runtime.ps1");
        string iconPath = Path.Combine(runtimeDirectory, "VibeList.ico");
        string errorLogPath = Path.Combine(runtimeDirectory, "error.log");

        try
        {
            Directory.CreateDirectory(runtimeDirectory);
            WriteResourceToFile("VibeList.ps1", scriptPath);
            WriteResourceToFile("VibeList.ico", iconPath);

            StringBuilder arguments = new StringBuilder();
            arguments.Append("-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File ");
            arguments.Append(Quote(scriptPath));

            foreach (string argument in args)
            {
                if (String.Equals(argument, "--smoke-test", StringComparison.OrdinalIgnoreCase))
                {
                    arguments.Append(" -SmokeTest");
                }
                else if (argument.StartsWith("--data-dir=", StringComparison.OrdinalIgnoreCase))
                {
                    string dataDirectory = argument.Substring("--data-dir=".Length).Trim('"');
                    arguments.Append(" -DataDirectory ");
                    arguments.Append(Quote(dataDirectory));
                }
            }

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                "WindowsPowerShell\\v1.0\\powershell.exe");
            startInfo.Arguments = arguments.ToString();
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.WindowStyle = ProcessWindowStyle.Hidden;
            startInfo.RedirectStandardError = true;
            startInfo.EnvironmentVariables["VIBELIST_ICON_PATH"] = iconPath;
            startInfo.EnvironmentVariables["VIBELIST_EXE_PATH"] = Assembly.GetExecutingAssembly().Location;
            startInfo.EnvironmentVariables["VIBELIST_LAUNCHER_PID"] = Process.GetCurrentProcess().Id.ToString();

            string errorOutput;
            int exitCode;
            using (Process process = Process.Start(startInfo))
            {
                errorOutput = process.StandardError.ReadToEnd();
                process.WaitForExit();
                exitCode = process.ExitCode;
            }

            if (exitCode != 0 || !String.IsNullOrWhiteSpace(errorOutput))
            {
                if (String.IsNullOrWhiteSpace(errorOutput))
                {
                    errorOutput = "PowerShell 종료 코드: " + exitCode;
                }
                throw new InvalidOperationException(errorOutput.Trim());
            }

            if (File.Exists(errorLogPath))
            {
                File.Delete(errorLogPath);
            }
            return 0;
        }
        catch (Exception exception)
        {
            string message = "Vibe List를 실행하지 못했습니다.\r\n\r\n" + exception.Message;
            try
            {
                Directory.CreateDirectory(runtimeDirectory);
                File.WriteAllText(errorLogPath, exception.ToString(), Encoding.UTF8);
                message += "\r\n\r\n오류 기록: " + errorLogPath;
            }
            catch { }

            MessageBox.Show(message, "Vibe List", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static string Quote(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static void WriteResourceToFile(string resourceName, string destinationPath)
    {
        Assembly assembly = Assembly.GetExecutingAssembly();
        using (Stream input = assembly.GetManifestResourceStream(resourceName))
        {
            if (input == null)
            {
                throw new InvalidOperationException("내장 리소스를 찾을 수 없습니다: " + resourceName);
            }
            using (FileStream output = new FileStream(destinationPath, FileMode.Create, FileAccess.Write, FileShare.Read))
            {
                input.CopyTo(output);
            }
        }
    }
}
