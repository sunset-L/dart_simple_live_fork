using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;

[assembly: AssemblyTitle("Simple Live Web")]
[assembly: AssemblyProduct("Simple Live Web")]

internal static class WindowsLauncher
{
    private static volatile bool cancelled;

    private static int Main()
    {
        Console.OutputEncoding = Encoding.UTF8;
        Console.Title = "Simple Live Web Portable";
        try
        {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(root, "scripts", "start-windows.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException("缺少启动脚本，请完整解压便携 ZIP。", script);

            var startInfo = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"),
                Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File " + (char)34 + script + (char)34 + " -Portable",
                WorkingDirectory = root,
                UseShellExecute = false
            };

            // PowerShell receives Ctrl+C in the shared console and owns service cleanup.
            Console.CancelKeyPress += delegate(object sender, ConsoleCancelEventArgs args)
            {
                cancelled = true;
                args.Cancel = true;
            };
            using (var child = Process.Start(startInfo))
            {
                child.WaitForExit();
                if (cancelled || child.ExitCode == 0)
                    return 0;
            }
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(error.Message);
        }

        Console.Error.WriteLine("启动失败，请查看上方提示及 README.md。");
        if (!cancelled && !Console.IsInputRedirected)
        {
            Console.WriteLine("按任意键关闭窗口。");
            Console.ReadKey(true);
        }
        return 1;
    }
}
