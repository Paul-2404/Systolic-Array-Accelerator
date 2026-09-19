import os
import math
import tkinter as tk
from tkinter import ttk, messagebox
import numpy as np
import torch
from torchvision import datasets, transforms
from PIL import Image, ImageTk

# ============================================================
# CONFIG & CONSTANTS
# ============================================================
ARRAY_DIM = 4
OUTPUT_DIR = "quantized_network"
PAGE_SIZE = 40  # Images per page in grid

class ImageSelectorApp:
    def __init__(self, root):
        self.root = root
        self.root.title("MNIST Hardware Input Selector (4-Image Pack)")
        self.root.geometry("980x750")
        self.root.configure(bg="#1e1e2e")

        # Styling
        self.style = ttk.Style()
        self.style.theme_use("clam")
        
        # Colors
        self.bg_color = "#1e1e2e"
        self.card_bg = "#252538"
        self.accent_color = "#89b4fa"
        self.selected_color = "#a6e3a1"
        self.text_color = "#cdd6f4"
        self.subtext_color = "#a6adc8"
        
        # Load Dataset
        self.status_var = tk.StringVar(value="Loading MNIST dataset...")
        self.create_header()

        self.transform = transforms.ToTensor()
        try:
            self.test_dataset = datasets.MNIST(
                root="./data",
                train=False,
                download=True,
                transform=self.transform
            )
            self.total_images = len(self.test_dataset)
        except Exception as e:
            messagebox.showerror("Dataset Error", f"Failed to load MNIST dataset:\n{e}")
            self.root.destroy()
            return

        self.selected_indices = []  # List of selected dataset indices (max 4)
        self.current_page = 0
        self.filter_digit = "All"

        self.photo_cache = {}  # Cache ImageTk objects to prevent garbage collection
        
        # UI Setup
        self.create_selection_panel()
        self.create_controls()
        self.create_grid()
        self.create_footer()

        self.update_page()
        self.status_var.set("Ready. Click images below to fill slots 1-4.")

    def create_header(self):
        header_frame = tk.Frame(self.root, bg=self.bg_color, pady=10, padx=20)
        header_frame.pack(fill="x")

        title = tk.Label(
            header_frame, 
            text="MNIST Hardware Input Pack Generator", 
            font=("Segoe UI", 16, "bold"), 
            fg=self.accent_color, 
            bg=self.bg_color
        )
        title.pack(anchor="w")

        subtitle = tk.Label(
            header_frame, 
            text="Select exactly 4 images to pack into 32-bit hardware words for your neural network input array.", 
            font=("Segoe UI", 10), 
            fg=self.subtext_color, 
            bg=self.bg_color
        )
        subtitle.pack(anchor="w")

    def create_selection_panel(self):
        panel_frame = tk.LabelFrame(
            self.root, 
            text=" Selected Input Images (Slots 1 to 4) ", 
            font=("Segoe UI", 11, "bold"),
            fg=self.accent_color,
            bg=self.card_bg,
            bd=1,
            relief="solid",
            padx=15,
            pady=10
        )
        panel_frame.pack(fill="x", padx=20, pady=10)

        self.slots_frame = tk.Frame(panel_frame, bg=self.card_bg)
        self.slots_frame.pack(fill="x")

        self.slot_widgets = []
        for i in range(ARRAY_DIM):
            slot_box = tk.Frame(
                self.slots_frame, 
                bg="#181825", 
                bd=2, 
                relief="groove", 
                width=180, 
                height=110
            )
            slot_box.pack_propagate(False)
            slot_box.grid(row=0, column=i, padx=10, pady=5)

            title_lbl = tk.Label(
                slot_box, 
                text=f"Slot {i+1} (Image {i})", 
                font=("Segoe UI", 9, "bold"), 
                fg=self.accent_color, 
                bg="#181825"
            )
            title_lbl.pack(pady=2)

            img_lbl = tk.Label(slot_box, text="Empty", fg=self.subtext_color, bg="#181825")
            img_lbl.pack(expand=True)

            info_lbl = tk.Label(slot_box, text="-", font=("Segoe UI", 9), fg=self.text_color, bg="#181825")
            info_lbl.pack(pady=2)

            # Click slot to clear it
            slot_box.bind("<Button-1>", lambda e, slot=i: self.clear_slot(slot))
            img_lbl.bind("<Button-1>", lambda e, slot=i: self.clear_slot(slot))
            info_lbl.bind("<Button-1>", lambda e, slot=i: self.clear_slot(slot))

            self.slot_widgets.append({
                "box": slot_box,
                "img": img_lbl,
                "info": info_lbl
            })

    def create_controls(self):
        ctrl_frame = tk.Frame(self.root, bg=self.bg_color, padx=20, pady=5)
        ctrl_frame.pack(fill="x")

        # Filter by digit dropdown
        filter_label = tk.Label(ctrl_frame, text="Filter Digit:", font=("Segoe UI", 10), fg=self.text_color, bg=self.bg_color)
        filter_label.pack(side="left", padx=(0, 5))

        self.digit_combo = ttk.Combobox(
            ctrl_frame, 
            values=["All"] + [str(d) for d in range(10)], 
            state="readonly", 
            width=8,
            font=("Segoe UI", 10)
        )
        self.digit_combo.current(0)
        self.digit_combo.pack(side="left", padx=(0, 20))
        self.digit_combo.bind("<<ComboboxSelected>>", self.on_filter_change)

        # Pagination controls
        self.btn_prev = tk.Button(
            ctrl_frame, 
            text="◀ Prev Page", 
            command=self.prev_page,
            bg="#313244", 
            fg=self.text_color, 
            activebackground="#45475a",
            activeforeground=self.text_color,
            relief="flat",
            font=("Segoe UI", 9, "bold"),
            padx=10
        )
        self.btn_prev.pack(side="left", padx=5)

        self.page_label = tk.Label(ctrl_frame, text="Page 1", font=("Segoe UI", 10, "bold"), fg=self.text_color, bg=self.bg_color)
        self.page_label.pack(side="left", padx=10)

        self.btn_next = tk.Button(
            ctrl_frame, 
            text="Next Page ▶", 
            command=self.next_page,
            bg="#313244", 
            fg=self.text_color, 
            activebackground="#45475a",
            activeforeground=self.text_color,
            relief="flat",
            font=("Segoe UI", 9, "bold"),
            padx=10
        )
        self.btn_next.pack(side="left", padx=5)

        # Export button
        self.btn_export = tk.Button(
            ctrl_frame, 
            text="💾 Export Quantized Input Files", 
            command=self.export_inputs,
            bg=self.selected_color, 
            fg="#11111b", 
            activebackground="#89dceb",
            activeforeground="#11111b",
            font=("Segoe UI", 10, "bold"),
            padx=15,
            pady=3,
            relief="flat"
        )
        self.btn_export.pack(side="right")

    def create_grid(self):
        grid_outer = tk.Frame(self.root, bg=self.bg_color, padx=20, pady=5)
        grid_outer.pack(fill="both", expand=True)

        self.canvas = tk.Canvas(grid_outer, bg="#11111b", highlightthickness=0)
        scrollbar = ttk.Scrollbar(grid_outer, orient="vertical", command=self.canvas.yview)
        
        self.grid_inner = tk.Frame(self.canvas, bg="#11111b")
        self.grid_inner.bind("<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))

        self.canvas.create_window((0, 0), window=self.grid_inner, anchor="nw")
        self.canvas.configure(yscrollcommand=scrollbar.set)

        self.canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

    def create_footer(self):
        footer_frame = tk.Frame(self.root, bg="#181825", pady=5, padx=20)
        footer_frame.pack(fill="x", side="bottom")

        status_lbl = tk.Label(
            footer_frame, 
            textvariable=self.status_var, 
            font=("Segoe UI", 9), 
            fg=self.subtext_color, 
            bg="#181825"
        )
        status_lbl.pack(side="left")

    def get_filtered_indices(self):
        if self.filter_digit == "All":
            return list(range(self.total_images))
        
        target_digit = int(self.filter_digit)
        # Filter matching dataset indices
        indices = []
        for i in range(self.total_images):
            _, label = self.test_dataset[i]
            if label == target_digit:
                indices.append(i)
        return indices

    def on_filter_change(self, event=None):
        self.filter_digit = self.digit_combo.get()
        self.current_page = 0
        self.update_page()

    def prev_page(self):
        if self.current_page > 0:
            self.current_page -= 1
            self.update_page()

    def next_page(self):
        filtered = self.get_filtered_indices()
        max_pages = math.ceil(len(filtered) / PAGE_SIZE)
        if self.current_page < max_pages - 1:
            self.current_page += 1
            self.update_page()

    def update_page(self):
        filtered_indices = self.get_filtered_indices()
        total_filtered = len(filtered_indices)
        max_pages = max(1, math.ceil(total_filtered / PAGE_SIZE))

        self.page_label.config(text=f"Page {self.current_page + 1} of {max_pages}")

        # Clear existing grid widgets
        for widget in self.grid_inner.winfo_children():
            widget.destroy()

        start_idx = self.current_page * PAGE_SIZE
        end_idx = min(start_idx + PAGE_SIZE, total_filtered)

        cols = 8
        self.photo_cache.clear()

        for grid_pos, idx_in_filtered in enumerate(range(start_idx, end_idx)):
            ds_index = filtered_indices[idx_in_filtered]
            image_tensor, label = self.test_dataset[ds_index]

            # Convert to PIL Image for rendering
            img_arr = (image_tensor.squeeze().numpy() * 255).astype(np.uint8)
            pil_img = Image.fromarray(img_arr).resize((56, 56), Image.NEAREST)
            photo = ImageTk.PhotoImage(pil_img)
            self.photo_cache[ds_index] = photo

            r = grid_pos // cols
            c = grid_pos % cols

            is_selected = ds_index in self.selected_indices
            slot_num = self.selected_indices.index(ds_index) + 1 if is_selected else None

            box_bg = "#252538" if not is_selected else "#2d3840"
            border_col = self.accent_color if not is_selected else self.selected_color

            card = tk.Frame(
                self.grid_inner, 
                bg=box_bg, 
                bd=2 if is_selected else 1, 
                relief="solid", 
                padx=5, 
                pady=5
            )
            card.grid(row=r, column=c, padx=6, pady=6)

            # Badge / Label text
            head_txt = f"#{ds_index} (Label: {label})"
            if is_selected:
                head_txt = f"★ SLOT {slot_num} | #{ds_index}"

            head_lbl = tk.Label(
                card, 
                text=head_txt, 
                font=("Segoe UI", 8, "bold" if is_selected else "normal"), 
                fg=self.selected_color if is_selected else self.subtext_color, 
                bg=box_bg
            )
            head_lbl.pack()

            img_btn = tk.Label(card, image=photo, bg=box_bg, cursor="hand2")
            img_btn.pack(pady=2)

            # Bind click
            for w in (card, head_lbl, img_btn):
                w.bind("<Button-1>", lambda e, idx=ds_index: self.toggle_select(idx))

        self.update_slots_ui()

    def toggle_select(self, ds_index):
        if ds_index in self.selected_indices:
            self.selected_indices.remove(ds_index)
            self.status_var.set(f"Removed image #{ds_index} from selection.")
        else:
            if len(self.selected_indices) >= ARRAY_DIM:
                self.status_var.set("Maximum 4 images allowed! Click a slot or selected image to unselect.")
                messagebox.showwarning("Selection Full", "You have already selected 4 images. Click a slot or image to remove it first.")
                return
            self.selected_indices.append(ds_index)
            self.status_var.set(f"Added image #{ds_index} to Slot {len(self.selected_indices)}.")

        self.update_page()

    def clear_slot(self, slot_idx):
        if slot_idx < len(self.selected_indices):
            removed = self.selected_indices.pop(slot_idx)
            self.status_var.set(f"Cleared Slot {slot_idx + 1} (Image #{removed}).")
            self.update_page()

    def update_slots_ui(self):
        for i in range(ARRAY_DIM):
            widget = self.slot_widgets[i]
            if i < len(self.selected_indices):
                ds_index = self.selected_indices[i]
                image_tensor, label = self.test_dataset[ds_index]

                img_arr = (image_tensor.squeeze().numpy() * 255).astype(np.uint8)
                pil_img = Image.fromarray(img_arr).resize((48, 48), Image.NEAREST)
                photo = ImageTk.PhotoImage(pil_img)
                self.photo_cache[f"slot_{i}"] = photo

                widget["box"].config(bg="#1e2a22", relief="solid")
                widget["img"].config(image=photo, text="", bg="#1e2a22")
                widget["info"].config(text=f"#{ds_index} | Label: {label}", fg=self.selected_color, bg="#1e2a22")
            else:
                widget["box"].config(bg="#181825", relief="groove")
                widget["img"].config(image="", text="Empty\n(Click to select)", fg=self.subtext_color, bg="#181825")
                widget["info"].config(text="-", fg=self.text_color, bg="#181825")

    def export_inputs(self):
        if len(self.selected_indices) < ARRAY_DIM:
            messagebox.showerror(
                "Incomplete Selection", 
                f"Please select exactly {ARRAY_DIM} images before exporting.\nCurrently selected: {len(self.selected_indices)}/4"
            )
            return

        def convert_image_to_hw(image):
            image = image.numpy().reshape(-1)
            image = np.round(image * 127.0)
            image = np.clip(image, 0, 127)
            return image.astype(np.int8)

        images = []
        labels = []

        for ds_index in self.selected_indices:
            image_tensor, label = self.test_dataset[ds_index]
            images.append(convert_image_to_hw(image_tensor))
            labels.append(label)

        images = np.array(images, dtype=np.int8)

        input_words = []
        for feature in range(784):
            word = 0
            for image_idx in range(ARRAY_DIM):
                value = int(images[image_idx, feature]) & 0xFF
                word |= (value << (8 * image_idx))
            input_words.append(word)

        input_words = np.array(input_words, dtype=np.uint32)

        os.makedirs(OUTPUT_DIR, exist_ok=True)

        bin_path = os.path.join(OUTPUT_DIR, "input_4_images.bin")
        npy_path = os.path.join(OUTPUT_DIR, "input_4_images.npy")
        txt_path = os.path.join(OUTPUT_DIR, "input_labels.txt")

        input_words.tofile(bin_path)
        np.save(npy_path, input_words)

        with open(txt_path, "w") as f:
            for lbl in labels:
                f.write(f"{lbl}\n")

        msg = (
            f"Successfully exported selected 4 images!\n\n"
            f"Selected Dataset Indices: {self.selected_indices}\n"
            f"Labels: {labels}\n\n"
            f"Files created in '{OUTPUT_DIR}/':\n"
            f"  • input_4_images.bin\n"
            f"  • input_4_images.npy\n"
            f"  • input_labels.txt"
        )

        messagebox.showinfo("Export Success", msg)
        self.status_var.set(f"Exported indices {self.selected_indices} (labels: {labels}) to {OUTPUT_DIR}/")

if __name__ == "__main__":
    root = tk.Tk()
    app = ImageSelectorApp(root)
    root.mainloop()
