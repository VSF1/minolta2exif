#!/usr/bin/env python3
#
# minolta2exif_ui.py
#
# (C) 2025 Vitor Fonseca
# Released under GNU General Public License v3
# http://www.vitorfonseca.com
#
# This script provides a GUI for minolta2exif.py.
#

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import json
import os
import sys
import glob
from threading import Thread
from queue import Queue

import minolta_exif_lib

SCRIPT_VERSION = "v1.0-UI"
CONFIG_FILE = "config.json"

class UILogger:
    def __init__(self, text_widget):
        self.text_widget = text_widget

    def write(self, message):
        self.text_widget.config(state=tk.NORMAL)
        self.text_widget.insert(tk.END, message)
        self.text_widget.see(tk.END)
        self.text_widget.config(state=tk.DISABLED)

    def flush(self):
        pass

class MinoltaExifApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title(f"Minolta to EXIF Converter {SCRIPT_VERSION}")
        self.geometry("800x600")

        self.settings = {}
        self.load_settings()

        self._create_widgets()
        self._populate_settings()

        self.protocol("WM_DELETE_WINDOW", self.on_closing)

    def _create_widgets(self):
        main_frame = ttk.Frame(self, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)

        # --- Settings Frame ---
        settings_frame = ttk.LabelFrame(main_frame, text="Settings", padding="10")
        settings_frame.pack(fill=tk.X, pady=5)

        ttk.Label(settings_frame, text="Camera Maker:").grid(row=0, column=0, sticky=tk.W, padx=5, pady=2)
        self.maker_var = tk.StringVar()
        ttk.Entry(settings_frame, textvariable=self.maker_var).grid(row=0, column=1, sticky=tk.EW, padx=5)

        ttk.Label(settings_frame, text="Camera Model:").grid(row=1, column=0, sticky=tk.W, padx=5, pady=2)
        self.model_var = tk.StringVar()
        ttk.Entry(settings_frame, textvariable=self.model_var).grid(row=1, column=1, sticky=tk.EW, padx=5)

        ttk.Label(settings_frame, text="Camera Serial:").grid(row=0, column=2, sticky=tk.W, padx=5, pady=2)
        self.serial_var = tk.StringVar()
        ttk.Entry(settings_frame, textvariable=self.serial_var).grid(row=0, column=3, sticky=tk.EW, padx=5)

        ttk.Label(settings_frame, text="Artist Name:").grid(row=1, column=2, sticky=tk.W, padx=5, pady=2)
        self.artist_var = tk.StringVar()
        ttk.Entry(settings_frame, textvariable=self.artist_var).grid(row=1, column=3, sticky=tk.EW, padx=5)

        settings_frame.columnconfigure(1, weight=1)
        settings_frame.columnconfigure(3, weight=1)

        # --- Input Frame ---
        input_frame = ttk.LabelFrame(main_frame, text="Inputs", padding="10")
        input_frame.pack(fill=tk.X, pady=5)

        ttk.Label(input_frame, text="Image Directory:").grid(row=0, column=0, sticky=tk.W, padx=5, pady=2)
        self.dir_var = tk.StringVar()
        ttk.Entry(input_frame, textvariable=self.dir_var).grid(row=0, column=1, sticky=tk.EW, padx=5)
        ttk.Button(input_frame, text="Browse...", command=self.browse_directory).grid(row=0, column=2, padx=5)

        ttk.Label(input_frame, text="Filename Pattern:").grid(row=1, column=0, sticky=tk.W, padx=5, pady=2)
        self.pattern_var = tk.StringVar()
        ttk.Entry(input_frame, textvariable=self.pattern_var).grid(row=1, column=1, columnspan=2, sticky=tk.EW, padx=5)

        pattern_help_text = "Use @F for frame, @U for Up-No, @R for roll. Ex: MyRoll-@R-@F.jpg"
        ttk.Label(input_frame, text=pattern_help_text, font=("", 8)).grid(row=2, column=1, columnspan=2, sticky=tk.W, padx=5)


        ttk.Label(input_frame, text="DNO Files:").grid(row=3, column=0, sticky=tk.NW, padx=5, pady=2)
        self.dno_listbox = tk.Listbox(input_frame, selectmode=tk.EXTENDED, height=4)
        self.dno_listbox.grid(row=3, column=1, sticky=tk.EW, padx=5)
        dno_button_frame = ttk.Frame(input_frame)
        dno_button_frame.grid(row=3, column=2, sticky=tk.NS)
        ttk.Button(dno_button_frame, text="Add...", command=self.add_dno_files).pack(fill=tk.X)
        ttk.Button(dno_button_frame, text="Remove", command=self.remove_dno_files).pack(fill=tk.X)

        input_frame.columnconfigure(1, weight=1)

        # --- Action Frame ---
        action_frame = ttk.Frame(main_frame, padding="10")
        action_frame.pack(fill=tk.X)
        self.run_button = ttk.Button(action_frame, text="Run Conversion", command=self.run_conversion)
        self.run_button.pack(side=tk.RIGHT)

        # --- Log Frame ---
        log_frame = ttk.LabelFrame(main_frame, text="Log", padding="10")
        log_frame.pack(fill=tk.BOTH, expand=True, pady=5)
        self.log_text = tk.Text(log_frame, wrap=tk.WORD, state=tk.DISABLED)
        log_scroll = ttk.Scrollbar(log_frame, orient=tk.VERTICAL, command=self.log_text.yview)
        self.log_text['yscrollcommand'] = log_scroll.set
        log_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.log_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

    def load_settings(self):
        try:
            with open(CONFIG_FILE, 'r') as f:
                self.settings = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            self.settings = {
                "CAMERA_MAKER": "Minolta",
                "CAMERA_MODEL": "Dynax 9",
                "CAMERA_SERIAL": "00000000",
                "ARTIST_NAME": "",
                "IMAGE_DIR": "",
                "PATTERN": "img-@R-@F.jpg"
            }

    def save_settings(self):
        self.settings['CAMERA_MAKER'] = self.maker_var.get()
        self.settings['CAMERA_MODEL'] = self.model_var.get()
        self.settings['CAMERA_SERIAL'] = self.serial_var.get()
        self.settings['ARTIST_NAME'] = self.artist_var.get()
        self.settings['IMAGE_DIR'] = self.dir_var.get()
        self.settings['PATTERN'] = self.pattern_var.get()
        with open(CONFIG_FILE, 'w') as f:
            json.dump(self.settings, f, indent=4)

    def _populate_settings(self):
        self.maker_var.set(self.settings.get("CAMERA_MAKER", "Minolta"))
        self.model_var.set(self.settings.get("CAMERA_MODEL", "Dynax 9"))
        self.serial_var.set(self.settings.get("CAMERA_SERIAL", "00000000"))
        self.artist_var.set(self.settings.get("ARTIST_NAME", ""))
        self.dir_var.set(self.settings.get("IMAGE_DIR", os.getcwd()))
        self.pattern_var.set(self.settings.get("PATTERN", ""))

    def on_closing(self):
        self.save_settings()
        self.destroy()

    def browse_directory(self):
        directory = filedialog.askdirectory(initialdir=self.dir_var.get())
        if directory:
            self.dir_var.set(directory)

    def add_dno_files(self):
        files = filedialog.askopenfilenames(
            title="Select DNO files",
            filetypes=(("Text files", "*.txt"), ("All files", "*.*"))
        )
        for f in files:
            if f not in self.dno_listbox.get(0, tk.END):
                self.dno_listbox.insert(tk.END, f)

    def remove_dno_files(self):
        selected = self.dno_listbox.curselection()
        for i in reversed(selected):
            self.dno_listbox.delete(i)

    def run_conversion(self):
        self.run_button.config(state=tk.DISABLED, text="Running...")
        
        # Get params from UI
        image_dir = self.dir_var.get()
        pattern = self.pattern_var.get()
        dno_files = self.dno_listbox.get(0, tk.END)
        
        if not os.path.isdir(image_dir):
            messagebox.showerror("Error", "Image directory does not exist.")
            self.run_button.config(state=tk.NORMAL, text="Run Conversion")
            return
        if not pattern:
            messagebox.showerror("Error", "Filename pattern cannot be empty.")
            self.run_button.config(state=tk.NORMAL, text="Run Conversion")
            return
        if not dno_files:
            messagebox.showerror("Error", "Please select at least one DNO file.")
            self.run_button.config(state=tk.NORMAL, text="Run Conversion")
            return

        # Redirect stdout/stderr to the log widget
        logger = UILogger(self.log_text)
        sys.stdout = logger
        sys.stderr = logger

        # Run in a separate thread to keep UI responsive
        thread = Thread(target=self.conversion_worker, args=(image_dir, pattern, dno_files))
        thread.start()

    def conversion_worker(self, image_dir, pattern_arg, dno_files):
        try:
            os.chdir(image_dir)
            print(f"Changed directory to: {image_dir}\n")

            image_extensions = ('*.jpg', '*.jpeg', '*.tif', '*.tiff', '*.dng')
            all_images = []
            for ext in image_extensions:
                all_images.extend(glob.glob(ext, recursive=False))
                all_images.extend(glob.glob(ext.upper(), recursive=False))

            current_settings = {
                "CAMERA_MAKER": self.maker_var.get(),
                "CAMERA_MODEL": self.model_var.get(),
                "CAMERA_SERIAL": self.serial_var.get(),
                "ARTIST_NAME": self.artist_var.get(),
            }

            for dno_file in dno_files:
                minolta_exif_lib.process_dno_file(dno_file, pattern_arg, all_images, current_settings, sys.stdout)
            
            print("\nConversion finished successfully!")

        except Exception as e:
            print(f"\nAn error occurred: {e}")
        finally:
            self.run_button.config(state=tk.NORMAL, text="Run Conversion")

if __name__ == "__main__":
    app = MinoltaExifApp()
    app.mainloop()