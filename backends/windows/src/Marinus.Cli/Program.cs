using Marinus.Cli;
using Marinus.Windows;

using var cancellation = new CancellationTokenSource();
Console.CancelKeyPress += (_, args) => { args.Cancel = true; cancellation.Cancel(); };
return await CliRunner.RunAsync(args, new WindowsScanner(), Console.Out, Console.Error, cancellation.Token);
