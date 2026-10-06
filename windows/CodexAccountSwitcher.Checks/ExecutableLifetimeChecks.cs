using CodexAccountSwitcher.Core;

internal static class ExecutableLifetimeChecks
{
    public static int Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "switcher-executable-check-" + Guid.NewGuid());
        Directory.CreateDirectory(root);
        var executable = Path.Combine(root, "Switcher.exe");
        var moved = Path.Combine(root, "Moved.exe");
        byte[] original = [1, 2, 3];
        try {
            File.WriteAllBytes(executable, original);
            using (ExecutableLifetime.Protect(executable)) {
                Require(File.ReadAllBytes(executable).SequenceEqual(original), "Read-only inspection must remain available.");
                RejectChange(() => File.Move(executable, moved));
                RejectChange(() => File.Delete(executable));
                RejectChange(() => File.WriteAllBytes(executable, [4, 5, 6]));
                Require(File.Exists(executable) && !File.Exists(moved), "The running bundle must remain at its original path.");
                Require(File.ReadAllBytes(executable).SequenceEqual(original), "The running bundle must remain unchanged.");
            }
            File.Move(executable, moved);
            Require(File.Exists(moved), "Normal replacement must be possible after shutdown releases the bundle.");
            File.Delete(moved);
            Console.WriteLine("PASS: the running executable cannot be moved, deleted or overwritten; reads and replacement after shutdown work.");
            return 0;
        } catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        finally { SecureFiles.DeleteOwnedDirectory(Path.GetTempPath(), root); }
    }

    private static void RejectChange(Action action)
    {
        try { action(); }
        catch (IOException error) when ((error.HResult & 0xFFFF) == 32) { return; }
        throw new IOException("A change to the protected executable did not fail with a sharing violation.");
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new IOException(message);
    }
}
