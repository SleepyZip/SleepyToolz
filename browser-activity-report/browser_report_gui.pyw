#!/usr/bin/env python3
"""
browser_report_gui.py — desktop front end for chrome_activity_report.py

Drop Chrome/Edge History databases in, get one formatted workbook per user out.
Files from any number of machines can be loaded at once; each row's User and
Workstation are parsed from the filename and can be corrected in place before
running (double-click a cell).

Requires : openpyxl, tzdata   (pip install openpyxl tzdata)
Optional : tkinterdnd2        (pip install tkinterdnd2)  -> real drag and drop
           Without it everything still works via the Add Files button.

Keep this file next to chrome_activity_report.py.
"""

import os
import queue
import subprocess
import sys
import threading
import traceback
from datetime import datetime

import tkinter as tk
from tkinter import filedialog, messagebox, ttk


def crash_log_path():
    """Somewhere writable regardless of how the app was launched."""
    base = os.path.join(os.path.expanduser("~"), "Documents")
    if not os.path.isdir(base):
        base = os.path.expanduser("~")
    return os.path.join(base, "BrowserReport_error.log")


def report_startup_error(title, detail):
    """Write the error to a log file AND try to show it, so a double-click
    launch that dies still leaves something readable behind."""
    path = crash_log_path()
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(f"\n===== {stamp}  {title} =====\n{detail}\n")
    except Exception:
        path = "(could not write log file)"

    msg = f"{title}\n\n{detail}\n\nSaved to:\n{path}"
    try:
        r = tk.Tk()
        r.withdraw()
        messagebox.showerror("Browser Activity Report - startup error", msg)
        r.destroy()
    except Exception:
        # No display at all -- fall back to stderr for the terminal case.
        sys.stderr.write(msg + "\n")


def load_engine():
    """Import the report engine, turning the common failures into clear text."""
    # When frozen by PyInstaller the bundled modules live in sys._MEIPASS.
    if getattr(sys, "frozen", False):
        meipass = getattr(sys, "_MEIPASS", "")
        if meipass and meipass not in sys.path:
            sys.path.insert(0, meipass)
    else:
        # Running as a plain script: make sure our own folder is importable
        # even if the working directory is elsewhere.
        here = os.path.dirname(os.path.abspath(__file__))
        if here not in sys.path:
            sys.path.insert(0, here)

    try:
        import chrome_activity_report as engine
        return engine
    except ImportError as exc:
        name = getattr(exc, "name", "") or ""
        if name == "chrome_activity_report":
            raise SystemExit(
                "chrome_activity_report.py is not in the same folder as this program.\n"
                "Put both files in one folder and start it again.")
        if name in ("openpyxl", "et_xmlfile"):
            raise SystemExit(
                "The 'openpyxl' package is missing.\n"
                "Install it with:  pip install openpyxl tzdata")
        raise SystemExit(f"A required package is missing: {name}\n{exc}")


# Optional drag-and-drop support. A broken/partial install can raise more than
# ImportError, so catch broadly and just fall back to the Add Files button.
try:
    from tkinterdnd2 import DND_FILES, TkinterDnD
    DND = True
except Exception:
    DND = False

PAD = 10
MONO = ("Consolas", 9) if sys.platform == "win32" else ("DejaVu Sans Mono", 9)

# Populated by main() at startup via load_engine().
engine = None


class ReportApp:
    def __init__(self, root):
        self.root = root
        root.title("Browser Activity Report")
        root.geometry("1000x720")
        root.minsize(860, 620)

        self.rows = {}          # tree iid -> [path, user, workstation]
        self.msgq = queue.Queue()
        self.running = False

        self._build()
        self.root.after(100, self._drain)

    # ------------------------------------------------------------ layout --
    def _build(self):
        outer = ttk.Frame(self.root, padding=PAD)
        outer.pack(fill="both", expand=True)

        # --- source files -------------------------------------------------
        box = ttk.LabelFrame(outer, text="1. Capture files", padding=PAD)
        box.pack(fill="both", expand=True)

        hint = ("Drag History files here, or use Add Files."
                if DND else
                "Use Add Files or Add Folder. (pip install tkinterdnd2 for drag and drop)")
        ttk.Label(box, text=hint, foreground="#555").pack(anchor="w", pady=(0, 6))

        cols = ("file", "user", "workstation", "size")
        self.tree = ttk.Treeview(box, columns=cols, show="headings", height=9)
        for c, w, t in (("file", 380, "File"), ("user", 160, "User"),
                        ("workstation", 160, "Workstation"), ("size", 90, "Size (MB)")):
            self.tree.heading(c, text=t)
            self.tree.column(c, width=w, anchor="w")
        self.tree.column("size", anchor="e")

        sb = ttk.Scrollbar(box, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=sb.set)
        self.tree.pack(side="left", fill="both", expand=True)
        sb.pack(side="left", fill="y")
        self.tree.bind("<Double-1>", self._edit_cell)

        if DND:
            self.tree.drop_target_register(DND_FILES)
            self.tree.dnd_bind("<<Drop>>", self._on_drop)

        btns = ttk.Frame(box)
        btns.pack(side="left", fill="y", padx=(PAD, 0))
        for label, cmd in (("Add Files", self.add_files),
                           ("Add Folder", self.add_folder),
                           ("Remove", self.remove_sel),
                           ("Clear", self.clear_all)):
            ttk.Button(btns, text=label, width=12, command=cmd).pack(pady=2)
        ttk.Label(btns, text="Double-click\na cell to edit",
                  foreground="#777", justify="center").pack(pady=(10, 0))

        # --- options ------------------------------------------------------
        opt = ttk.LabelFrame(outer, text="2. Options", padding=PAD)
        opt.pack(fill="x", pady=(PAD, 0))

        ttk.Label(opt, text="Date range (MM-DD-YYYY, optional):").grid(
            row=0, column=0, sticky="w", columnspan=2)
        self.start = tk.StringVar()
        self.end = tk.StringVar()
        ttk.Label(opt, text="From").grid(row=1, column=0, sticky="e", padx=(0, 4))
        ttk.Entry(opt, textvariable=self.start, width=14).grid(row=1, column=1, sticky="w")
        ttk.Label(opt, text="To").grid(row=1, column=2, sticky="e", padx=(PAD, 4))
        ttk.Entry(opt, textvariable=self.end, width=14).grid(row=1, column=3, sticky="w")
        ttk.Label(opt, text="blank = all available",
                  foreground="#777").grid(row=1, column=4, sticky="w", padx=(PAD, 0))

        self.keep_noise = tk.BooleanVar(value=False)
        self.keep_sub = tk.BooleanVar(value=False)
        self.keep_redir = tk.BooleanVar(value=False)
        ttk.Checkbutton(opt, text="Keep ad/tracker rows",
                        variable=self.keep_noise).grid(row=2, column=0, columnspan=2,
                                                       sticky="w", pady=(8, 0))
        ttk.Checkbutton(opt, text="Keep subframes (noisy)",
                        variable=self.keep_sub).grid(row=2, column=2, columnspan=2,
                                                     sticky="w", padx=(PAD, PAD),
                                                     pady=(8, 0))
        ttk.Checkbutton(opt, text="Keep redirect hops",
                        variable=self.keep_redir).grid(row=2, column=4,
                                                       sticky="w", padx=(PAD, 0),
                                                       pady=(8, 0))

        # --- output -------------------------------------------------------
        out = ttk.LabelFrame(outer, text="3. Output folder", padding=PAD)
        out.pack(fill="x", pady=(PAD, 0))
        self.outdir = tk.StringVar(
            value=os.path.join(os.path.expanduser("~"), "Documents", "BrowsingReports"))
        ttk.Entry(out, textvariable=self.outdir).pack(side="left", fill="x",
                                                      expand=True, padx=(0, 6))
        ttk.Button(out, text="Browse", width=10, command=self.pick_out).pack(side="left")

        # --- run ----------------------------------------------------------
        run = ttk.Frame(outer)
        run.pack(fill="x", pady=(PAD, 0))
        self.runbtn = ttk.Button(run, text="Generate Report",
                                 command=self.start_run, width=20)
        self.runbtn.pack(side="left")
        self.openbtn = ttk.Button(run, text="Open Output Folder",
                                  command=self.open_out, width=20, state="disabled")
        self.openbtn.pack(side="left", padx=(6, 0))
        self.bar = ttk.Progressbar(run, mode="determinate", maximum=100)
        self.bar.pack(side="left", fill="x", expand=True, padx=(PAD, 0))

        # --- log ----------------------------------------------------------
        logf = ttk.LabelFrame(outer, text="Log", padding=6)
        logf.pack(fill="both", expand=True, pady=(PAD, 0))
        self.log = tk.Text(logf, height=9, wrap="none", font=MONO,
                           background="#1e1e1e", foreground="#d4d4d4",
                           insertbackground="#d4d4d4")
        ls = ttk.Scrollbar(logf, orient="vertical", command=self.log.yview)
        self.log.configure(yscrollcommand=ls.set, state="disabled")
        self.log.pack(side="left", fill="both", expand=True)
        ls.pack(side="left", fill="y")

    # ------------------------------------------------------------- files --
    def _add_path(self, path):
        if not os.path.isfile(path):
            return 0
        base = os.path.basename(path)
        if base.endswith(("-wal", "-shm")):
            return 0
        if any(r[0] == path for r in self.rows.values()):
            return 0
        user, host = engine.parse_filename(engine.strip_ext(base))
        mb = round(os.path.getsize(path) / 1_048_576, 2)
        iid = self.tree.insert("", "end", values=(base, user, host, f"{mb:.2f}"))
        self.rows[iid] = [path, user, host]
        return 1

    def add_files(self):
        paths = filedialog.askopenfilenames(
            title="Select History databases",
            filetypes=[("All files", "*.*"), ("SQLite", "*.db *.sqlite")])
        n = sum(self._add_path(p) for p in paths)
        self._say(f"Added {n} file(s).")

    def add_folder(self):
        folder = filedialog.askdirectory(title="Folder containing History files")
        if not folder:
            return
        n = 0
        for name in sorted(os.listdir(folder)):
            if "history" in name.lower():
                n += self._add_path(os.path.join(folder, name))
        self._say(f"Added {n} file(s) from {folder}")

    def _on_drop(self, event):
        n = 0
        for p in self.tree.tk.splitlist(event.data):
            if os.path.isdir(p):
                for name in sorted(os.listdir(p)):
                    if "history" in name.lower():
                        n += self._add_path(os.path.join(p, name))
            else:
                n += self._add_path(p)
        self._say(f"Added {n} file(s).")

    def remove_sel(self):
        for iid in self.tree.selection():
            self.tree.delete(iid)
            self.rows.pop(iid, None)

    def clear_all(self):
        self.tree.delete(*self.tree.get_children())
        self.rows.clear()

    def _edit_cell(self, event):
        """In-place edit of the User / Workstation columns."""
        iid = self.tree.identify_row(event.y)
        col = self.tree.identify_column(event.x)
        if not iid or col not in ("#2", "#3"):
            return
        idx = 1 if col == "#2" else 2
        x, y, w, h = self.tree.bbox(iid, col)
        var = tk.StringVar(value=self.rows[iid][idx])
        ent = ttk.Entry(self.tree, textvariable=var)
        ent.place(x=x, y=y, width=w, height=h)
        ent.focus_set()
        ent.selection_range(0, "end")

        def commit(_=None):
            val = var.get().strip()
            if val:
                self.rows[iid][idx] = val
                vals = list(self.tree.item(iid, "values"))
                vals[idx] = val
                self.tree.item(iid, values=vals)
            ent.destroy()

        ent.bind("<Return>", commit)
        ent.bind("<FocusOut>", commit)
        ent.bind("<Escape>", lambda e: ent.destroy())

    def pick_out(self):
        d = filedialog.askdirectory(title="Output folder")
        if d:
            self.outdir.set(d)

    def open_out(self):
        d = self.outdir.get()
        if not os.path.isdir(d):
            return
        if sys.platform == "win32":
            os.startfile(d)
        elif sys.platform == "darwin":
            subprocess.Popen(["open", d])
        else:
            subprocess.Popen(["xdg-open", d])

    # --------------------------------------------------------------- run --
    def start_run(self):
        if self.running:
            return
        if not self.rows:
            messagebox.showwarning("Nothing to do", "Add at least one History file.")
            return

        tz, _ = engine.get_local_tz()
        start = end = None
        try:
            if self.start.get().strip():
                start = engine.parse_bound(self.start.get().strip()).replace(tzinfo=tz)
            if self.end.get().strip():
                end = engine.parse_bound(self.end.get().strip()).replace(
                    hour=23, minute=59, second=59, tzinfo=tz)
        except ValueError as exc:
            messagebox.showerror("Bad date", str(exc))
            return
        if start and end and start > end:
            messagebox.showerror("Bad range", "The From date is after the To date.")
            return

        entries = [(p, u, h) for p, u, h in self.rows.values()]
        outdir = self.outdir.get().strip()

        self.running = True
        self.runbtn.configure(state="disabled", text="Working...")
        self.openbtn.configure(state="disabled")
        self.bar["value"] = 0
        self._clear_log()

        opts = dict(keep_noise=self.keep_noise.get(),
                    keep_subframes=self.keep_sub.get(),
                    keep_redirects=self.keep_redir.get())
        threading.Thread(target=self._worker,
                         args=(entries, outdir, start, end, opts),
                         daemon=True).start()

    def _worker(self, entries, outdir, start, end, opts):
        def progress(msg, frac=None):
            self.msgq.put(("log", msg))
            if frac is not None:
                self.msgq.put(("bar", frac * 100))
        try:
            written, stats = engine.build_reports(
                entries, outdir, start, end, progress=progress, **opts)
            self.msgq.put(("done", (written, stats)))
        except Exception:
            self.msgq.put(("error", traceback.format_exc()))

    def _drain(self):
        try:
            while True:
                kind, payload = self.msgq.get_nowait()
                if kind == "log":
                    self._say(payload)
                elif kind == "bar":
                    self.bar["value"] = payload
                elif kind == "done":
                    self._finish(*payload)
                elif kind == "error":
                    self._say(payload)
                    self._reset()
                    messagebox.showerror("Failed", "See the log for details.")
        except queue.Empty:
            pass
        self.root.after(100, self._drain)

    def _finish(self, written, stats):
        self.bar["value"] = 100
        self._say("")
        if not written:
            self._say("No workbooks written. Check that the files are Chrome/Edge databases.")
        for path in written:
            user = os.path.basename(path)[len("Browsing_Activity_"):-len(".xlsx")]
            st = stats.get(user, {})
            self._say(f"{os.path.basename(path)}")
            self._say(f"    {st.get('visits', 0):,} visits, "
                      f"{st.get('high', 0):,} high-flag, "
                      f"{st.get('downloads', 0):,} downloads")
        self._reset()
        if written:
            self.openbtn.configure(state="normal")
            messagebox.showinfo("Finished",
                                f"Wrote {len(written)} workbook(s) to:\n{self.outdir.get()}")

    def _reset(self):
        self.running = False
        self.runbtn.configure(state="normal", text="Generate Report")

    # --------------------------------------------------------------- log --
    def _say(self, msg):
        self.log.configure(state="normal")
        self.log.insert("end", str(msg) + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def _clear_log(self):
        self.log.configure(state="normal")
        self.log.delete("1.0", "end")
        self.log.configure(state="disabled")


def main():
    # Load the engine here (not at import time) so a missing file or package
    # surfaces as a readable message instead of a silent flash-and-close.
    global engine
    engine = load_engine()

    root = TkinterDnD.Tk() if DND else tk.Tk()

    # Pick a theme that exists on this machine; builds vary.
    style = ttk.Style()
    for theme in (("vista", "winnative", "clam") if sys.platform == "win32"
                  else ("clam",)):
        if theme in style.theme_names():
            try:
                style.theme_use(theme)
                break
            except tk.TclError:
                continue

    ReportApp(root)
    root.mainloop()


if __name__ == "__main__":
    try:
        main()
    except SystemExit as exc:
        # load_engine() raises these with a friendly message.
        msg = str(exc)
        if msg and msg != "0":
            report_startup_error("Could not start", msg)
        raise
    except Exception:
        report_startup_error("Unexpected error at startup", traceback.format_exc())
        raise
