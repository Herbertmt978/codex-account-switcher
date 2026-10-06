namespace CodexAccountSwitcher.Core;

public static class ExecutableLifetime
{
    public static FileStream Protect() => Protect(Environment.ProcessPath
        ?? throw new IOException("The Account Switcher executable path is unavailable."));

    // Single-file bundles load assemblies on demand. Keep the bundle at its original
    // path until shutdown; moving it can otherwise cause a later FileNotFoundException.
    internal static FileStream Protect(string path) => new(path,
        FileMode.Open, FileAccess.Read, FileShare.Read);
}
