using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace ScreenAgent
{
    internal static class Config
    {
        public const string Endpoint = "http://127.0.0.1:8080/v1/chat/completions";
        public const string Model = "local";
        public const string SystemPrompt =
            "You are a screen assistant. Look at the image and answer the question it contains " +
            "directly and as briefly as possible - just the answer, nothing else, no explanation. " +
            "If it is a multiple-choice question, reply with the index of the correct option " +
            "(its number or letter) and the option text. Output only the final answer strictly " +
            "inside <result></result> tags.";

        // Hold these, then left-drag a box. All false = plain left-drag.
        public const bool RequireCtrl = true;
        public const bool RequireShift = true;
        public const bool RequireAlt = false;
    }

    // ------- Win32 -------
    internal static class Native
    {
        [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
        [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();

        [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
        [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr hDC);
        [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr hDC, IntPtr hObject);
        [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr hDC);
        [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr hObject);
        [DllImport("user32.dll")] public static extern bool UpdateLayeredWindow(
            IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc,
            ref POINT pptSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);

        public const int VK_LBUTTON = 0x01, VK_SHIFT = 0x10, VK_CONTROL = 0x11,
                         VK_MENU = 0x12, VK_ESCAPE = 0x1B;
        public const int ULW_ALPHA = 0x02;
        public const byte AC_SRC_OVER = 0x00, AC_SRC_ALPHA = 0x01;

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT { public int X; public int Y; public POINT(int x, int y) { X = x; Y = y; } }
        [StructLayout(LayoutKind.Sequential)]
        public struct SIZE { public int cx; public int cy; public SIZE(int x, int y) { cx = x; cy = y; } }
        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        public struct BLENDFUNCTION { public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat; }

        public static bool Down(int vKey) { return (GetAsyncKeyState(vKey) & 0x8000) != 0; }
        public static Point Cursor() { POINT p; GetCursorPos(out p); return new Point(p.X, p.Y); }
    }

    // ------- Screen capture + auto-crop -------
    internal static class ImgProc
    {
        public static string Process(int x, int y, int w, int h)
        {
            if (w <= 0 || h <= 0) return null;
            using (Bitmap bmp = new Bitmap(w, h))
            {
                using (Graphics g = Graphics.FromImage(bmp))
                    g.CopyFromScreen(x, y, 0, 0, new Size(w, h));

                int left = w, top = h, right = 0, bottom = 0;
                Color bg = bmp.GetPixel(0, 0);
                int tol = 40;

                for (int i = 0; i < w; i += 2)
                    for (int j = 0; j < h; j += 2)
                    {
                        Color c = bmp.GetPixel(i, j);
                        if (Math.Abs(c.R - bg.R) + Math.Abs(c.G - bg.G) + Math.Abs(c.B - bg.B) > tol)
                        {
                            if (i < left) left = i;
                            if (i > right) right = i;
                            if (j < top) top = j;
                            if (j > bottom) bottom = j;
                        }
                    }

                if (left > right || top > bottom) { left = 0; top = 0; right = w - 1; bottom = h - 1; }
                left = Math.Max(0, left - 6); top = Math.Max(0, top - 6);
                right = Math.Min(w - 1, right + 6); bottom = Math.Min(h - 1, bottom + 6);

                int cw = right - left + 1, ch = bottom - top + 1;
                using (Bitmap cropped = new Bitmap(cw, ch))
                {
                    using (Graphics cg = Graphics.FromImage(cropped))
                        cg.DrawImage(bmp, new Rectangle(0, 0, cw, ch),
                                     new Rectangle(left, top, cw, ch), GraphicsUnit.Pixel);
                    using (MemoryStream ms = new MemoryStream())
                    {
                        cropped.Save(ms, ImageFormat.Jpeg);
                        return Convert.ToBase64String(ms.ToArray());
                    }
                }
            }
        }
    }

    internal static class Json
    {
        public static string Escape(string s)
        {
            if (s == null) return "";
            StringBuilder sb = new StringBuilder(s.Length + 16);
            foreach (char c in s)
            {
                switch (c)
                {
                    case '\"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\b': sb.Append("\\b"); break;
                    case '\f': sb.Append("\\f"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4"));
                        else sb.Append(c);
                        break;
                }
            }
            return sb.ToString();
        }

        public static string ExtractContent(string body)
        {
            if (string.IsNullOrEmpty(body)) return null;
            int key = body.IndexOf("\"content\"", StringComparison.Ordinal);
            if (key < 0) return null;
            int i = body.IndexOf('"', key + 9);
            if (i < 0) return null;
            i++;
            StringBuilder sb = new StringBuilder();
            while (i < body.Length)
            {
                char c = body[i];
                if (c == '\\' && i + 1 < body.Length)
                {
                    char n = body[i + 1];
                    switch (n)
                    {
                        case '"': sb.Append('"'); break;
                        case '\\': sb.Append('\\'); break;
                        case '/': sb.Append('/'); break;
                        case 'b': sb.Append('\b'); break;
                        case 'f': sb.Append('\f'); break;
                        case 'n': sb.Append('\n'); break;
                        case 'r': sb.Append('\r'); break;
                        case 't': sb.Append('\t'); break;
                        case 'u':
                            if (i + 5 < body.Length)
                            { sb.Append((char)Convert.ToInt32(body.Substring(i + 2, 4), 16)); i += 4; }
                            break;
                        default: sb.Append(n); break;
                    }
                    i += 2;
                }
                else if (c == '"') break;
                else { sb.Append(c); i++; }
            }
            return sb.ToString();
        }
    }

    // ------- Transparent, auto-sizing result window with inverted (readable-on-anything) text -------
    internal sealed class InvertedResult : Form
    {
        private static readonly Font TextFont = new Font("Segoe UI", 8f, FontStyle.Regular);
        private const int PadX = 10, PadY = 6, MaxTextWidth = 340;
        private const int BorderAlpha = 28;
        private const int HitMargin = 16; // invisible click pad around the text
        private const int HitAlpha = 1;   // non-zero so clicks near the box register

        private readonly System.Windows.Forms.Timer _autoClose;

        public InvertedResult()
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            TopMost = true;
            _autoClose = new System.Windows.Forms.Timer();
            _autoClose.Interval = 25000;
            _autoClose.Tick += (s, e) => Close();
        }

        protected override CreateParams CreateParams
        {
            get
            {
                const int WS_EX_LAYERED = 0x80000, WS_EX_TOOLWINDOW = 0x80, WS_EX_NOACTIVATE = 0x8000000;
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
                return cp;
            }
        }
        protected override bool ShowWithoutActivation { get { return true; } }

        // Any click on or near the box dismisses it.
        protected override void OnMouseDown(MouseEventArgs e) { Close(); }
        protected override void OnMouseUp(MouseEventArgs e) { Close(); }

        public void ShowNear(string text, Point anchor)
        {
            if (string.IsNullOrEmpty(text)) text = "(no answer)";

            // 1. Measure (with wrapping) to size the window to the text.
            SizeF sz;
            using (Bitmap tmp = new Bitmap(1, 1))
            using (Graphics g = Graphics.FromImage(tmp))
            {
                g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                sz = g.MeasureString(text, TextFont, MaxTextWidth);
            }
            int tw = Math.Max(1, (int)Math.Ceiling(sz.Width)) + 2;
            int th = Math.Max(1, (int)Math.Ceiling(sz.Height)) + 2;
            int w = tw + PadX * 2 + HitMargin * 2;
            int h = th + PadY * 2 + HitMargin * 2;
            int textX = HitMargin + PadX, textY = HitMargin + PadY;

            // 2. Position next to the selection, clamped to the screen.
            int x = anchor.X, y = anchor.Y;
            Rectangle wa = Screen.GetWorkingArea(new Point(x, y));
            if (x + w > wa.Right) x = wa.Right - w;
            if (y + h > wa.Bottom) y = wa.Bottom - h;
            if (x < wa.Left) x = wa.Left;
            if (y < wa.Top) y = wa.Top;

            Bounds = new Rectangle(x, y, w, h);
            if (!Visible) Show();

            // 3. Capture what's behind the window, to invert the text against it.
            int[] back = new int[w * h];
            using (Bitmap bg = new Bitmap(w, h, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(bg))
                    g.CopyFromScreen(x, y, 0, 0, new Size(w, h));
                CopyInts(bg, back);
            }

            // 4. Render the text to a coverage mask.
            int[] mask = new int[w * h];
            using (Bitmap mb = new Bitmap(w, h, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(mb))
                {
                    g.Clear(Color.Black);
                    g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                    using (StringFormat fmt = new StringFormat())
                    using (Brush br = new SolidBrush(Color.White))
                        g.DrawString(text, TextFont, br, new RectangleF(textX, textY, tw, th), fmt);

                }
                CopyInts(mb, mask);
            }

            // 5. Compose premultiplied ARGB: transparent bg, faint border, inverted text.
            int[] outPx = new int[w * h];
            for (int i = 0; i < outPx.Length; i++)
            {
                int cov = (mask[i] >> 8) & 0xFF; // green channel = text coverage
                int px = i % w, py = i / w;
                bool edge = (px == HitMargin || py == HitMargin || px == w - 1 - HitMargin || py == h - 1 - HitMargin);
                if (cov > 0)
                {
                    int bp = back[i];
                    int ir = 255 - ((bp >> 16) & 0xFF);
                    int ig = 255 - ((bp >> 8) & 0xFF);
                    int ib = 255 - (bp & 0xFF);
                    outPx[i] = Pre(cov, ir, ig, ib);
                }
                else if (edge)
                    outPx[i] = Pre(BorderAlpha, 255, 255, 255);
                else
                    outPx[i] = Pre(HitAlpha, 0, 0, 0); // hittable, effectively invisible
            }

            PushLayered(outPx, x, y, w, h);
            _autoClose.Stop(); _autoClose.Start();
        }

        private static int Pre(int a, int r, int g, int b)
        {
            r = r * a / 255; g = g * a / 255; b = b * a / 255;
            return (a << 24) | (r << 16) | (g << 8) | b;
        }

        private static void CopyInts(Bitmap bmp, int[] dst)
        {
            Rectangle rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
            BitmapData d = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            Marshal.Copy(d.Scan0, dst, 0, dst.Length);
            bmp.UnlockBits(d);
        }

        private void PushLayered(int[] px, int x, int y, int w, int h)
        {
            Bitmap layer = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            Rectangle rect = new Rectangle(0, 0, w, h);
            BitmapData d = layer.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            Marshal.Copy(px, 0, d.Scan0, px.Length);
            layer.UnlockBits(d);

            IntPtr screenDc = Native.GetDC(IntPtr.Zero);
            IntPtr memDc = Native.CreateCompatibleDC(screenDc);
            IntPtr newHb = layer.GetHbitmap(Color.FromArgb(0));
            IntPtr oldHb = Native.SelectObject(memDc, newHb);

            Native.SIZE size = new Native.SIZE(w, h);
            Native.POINT src = new Native.POINT(0, 0);
            Native.POINT dst = new Native.POINT(x, y);
            Native.BLENDFUNCTION bf = new Native.BLENDFUNCTION();
            bf.BlendOp = Native.AC_SRC_OVER;
            bf.SourceConstantAlpha = 255;
            bf.AlphaFormat = Native.AC_SRC_ALPHA;

            Native.UpdateLayeredWindow(Handle, screenDc, ref dst, ref size, memDc, ref src, 0, ref bf, Native.ULW_ALPHA);

            Native.SelectObject(memDc, oldHb);
            Native.DeleteObject(newHb);
            Native.DeleteDC(memDc);
            Native.ReleaseDC(IntPtr.Zero, screenDc);
            layer.Dispose();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && _autoClose != null) _autoClose.Dispose();
            base.Dispose(disposing);
        }
    }

    // ------- Background controller: timer-polled drag detection + tray -------
    // Hidden message pump so the drag timer runs with no tray icon, taskbar button, or window.
    internal sealed class PumpWindow : NativeWindow
    {
        public PumpWindow()
        {
            CreateHandle(new CreateParams());
        }
    }

    internal sealed class AgentContext : ApplicationContext
    {
        private readonly PumpWindow _pump;
        private readonly System.Windows.Forms.Timer _timer;

        private bool _dragging, _busy;
        private Point _start, _last;
        private InvertedResult _result;

        public AgentContext()
        {
            _pump = new PumpWindow();
            _timer = new System.Windows.Forms.Timer();
            _timer.Interval = 15;
            _timer.Tick += Tick;
            _timer.Start();
        }

        private static string TriggerText()
        {
            string s = "";
            if (Config.RequireCtrl) s += "Ctrl+";
            if (Config.RequireShift) s += "Shift+";
            if (Config.RequireAlt) s += "Alt+";
            return s.Length == 0 ? "left" : s.TrimEnd(new char[] { '+' });
        }

        private static bool ModsHeld()
        {
            if (Config.RequireCtrl && !Native.Down(Native.VK_CONTROL)) return false;
            if (Config.RequireShift && !Native.Down(Native.VK_SHIFT)) return false;
            if (Config.RequireAlt && !Native.Down(Native.VK_MENU)) return false;
            return true;
        }

        private void Tick(object sender, EventArgs e)
        {
            // Esc dismisses an open answer. Ctrl+Shift+Q exits with no UI.
            if (Native.Down(Native.VK_ESCAPE) && _result != null && !_result.IsDisposed)
            { _result.Close(); _result = null; }
            if (Native.Down(Native.VK_CONTROL) && Native.Down(Native.VK_SHIFT) && Native.Down(0x51))
            { ExitThread(); return; }

            if (_busy) return;
            bool lbtn = Native.Down(Native.VK_LBUTTON);
            Point pos = Native.Cursor();

            if (!_dragging)
            {
                if (lbtn && ModsHeld()) { _dragging = true; _start = pos; _last = pos; }
            }
            else
            {
                if (lbtn) { _last = pos; }
                else
                {
                    _dragging = false;
                    Rectangle r = Normalize(_start, _last);
                    if (r.Width >= 10 && r.Height >= 10) DoCapture(r);
                }
            }
        }

        private static Rectangle Normalize(Point a, Point b)
        {
            return new Rectangle(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y),
                                 Math.Abs(a.X - b.X), Math.Abs(a.Y - b.Y));
        }

        private void DoCapture(Rectangle r)
        {
            _busy = true;
            try
            {
                if (_result != null && !_result.IsDisposed) _result.Close();
                Point anchor = new Point(r.Right + 10, r.Bottom + 10);

                string base64 = null;
                try { base64 = ImgProc.Process(r.X, r.Y, r.Width, r.Height); } catch { }

                string output;
                if (base64 == null) output = ":(";
                else
                {
                    try { output = CallGroq(base64); }
                    catch (Exception ex) { output = "Error: " + ex.Message; }
                }
                ShowResult(output, anchor);
            }
            finally { _busy = false; }
        }

        private void ShowResult(string text, Point anchor)
        {
            _result = new InvertedResult();
            _result.ShowNear(text, anchor);
        }

        private static string CallGroq(string base64Image)
        {
            string payload =
                "{\"model\":\"" + Json.Escape(Config.Model) + "\"," +
                "\"messages\":[" +
                    "{\"role\":\"system\",\"content\":\"" + Json.Escape(Config.SystemPrompt) + "\"}," +
                    "{\"role\":\"user\",\"content\":[" +
                        "{\"type\":\"text\",\"text\":\"Answer the question in this image.\"}," +
                        "{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/jpeg;base64," + base64Image + "\"}}" +
                    "]}" +
                "]," +
                "\"temperature\":0.2,\"max_tokens\":512}";

            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(Config.Endpoint);
            req.Method = "POST";
            req.ContentType = "application/json";
            req.Timeout = 120000;
            byte[] data = Encoding.UTF8.GetBytes(payload);
            req.ContentLength = data.Length;
            using (Stream rs = req.GetRequestStream()) rs.Write(data, 0, data.Length);

            string body;
            using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
            using (StreamReader sr = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                body = sr.ReadToEnd();

            string content = Json.ExtractContent(body) ?? "";
            content = Regex.Replace(content, "(?si)<think>.*?</think>", "");
            Match mm = Regex.Match(content, "(?si)<result>(.*?)</result>");
            string agentOutput = mm.Success ? mm.Groups[1].Value.Trim() : content.Trim();
            agentOutput = Regex.Replace(agentOutput, "\\\\boxed\\{([^}]+)\\}", "$1");
            agentOutput = agentOutput.Replace("**", "");
            agentOutput = Regex.Replace(agentOutput, "(?m)^\\s*\\$+|\\$+\\s*$", "");
            if (agentOutput.Length == 0) agentOutput = "(Err)";
            return agentOutput;
        }

        protected override void ExitThreadCore()
        {
            if (_timer != null) { _timer.Stop(); _timer.Dispose(); }
            if (_result != null && !_result.IsDisposed) _result.Close();
            if (_pump != null) _pump.DestroyHandle();
            base.ExitThreadCore();
        }
    }

    internal static class Program
    {
        [STAThread]
        static void Main()
        {
            bool created;
            Mutex mtx = new Mutex(true, "x", out created);
            if (!created) return;
            try
            {
                try { Native.SetProcessDPIAware(); } catch { }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new AgentContext());
            }
            catch
            {
            }
            finally { GC.KeepAlive(mtx); }
        }
    }
}
