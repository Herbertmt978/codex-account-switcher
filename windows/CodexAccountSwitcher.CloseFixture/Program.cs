using System.Drawing;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new QuitFixtureForm
        {
            Text = "Codex package update test fixture",
            ClientSize = new Size(360, 90),
            FormBorderStyle = FormBorderStyle.FixedToolWindow,
            StartPosition = FormStartPosition.CenterScreen,
            ShowInTaskbar = true
        });
    }
}

internal sealed class QuitFixtureForm : Form
{
    protected override bool ProcessCmdKey(ref Message message, Keys keyData)
    {
        if (keyData == (Keys.Control | Keys.Q))
        {
            Application.Exit();
            return true;
        }
        return base.ProcessCmdKey(ref message, keyData);
    }
}
