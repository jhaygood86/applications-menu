// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
//  
//  Copyright (C) 2011 Giulio Collura
// 
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
// 
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
// 
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

using Gtk;
using Gdk;
using Gee;
using Cairo;
using Granite.Widgets;
using GMenu;

using Slingshot.Widgets;
using Slingshot.Backend;

namespace Slingshot {

    public class SlingshotView : CompositedWindow {

        public ComboBoxText category_switcher;
        public SearchBar searchbar;
        public Widgets.Grid grid;
        public Layout pages;
        public Switcher page_switcher;
        public VBox grid_n_pages;

        private VBox container;

        private ArrayList<TreeDirectory> categories;
        private HashMap<string, ArrayList<App>> apps;
        private ArrayList<App> filtered;

        private int current_position = 0;

        public SlingshotView () {

            Slingshot.icon_theme = IconTheme.get_default ();

            set_size_request (700, 580);
            read_settings ();

            // Window properties
            this.title = "Slingshot";
            this.skip_pager_hint = true;
            this.skip_taskbar_hint = true;
            this.set_type_hint (Gdk.WindowTypeHint.NORMAL);
            this.set_keep_above (true);

            // No time to have slingshot resizable.
            this.resizable = false;
            this.app_paintable = true;

            // Have the window in the right place
            this.move (5, 0); 

            categories = AppSystem.get_categories ();
            apps = new HashMap<string, ArrayList<App>> ();

            foreach (TreeDirectory cat in categories) {
                apps.set (cat.get_name (), AppSystem.get_apps (cat));
            }

            filtered = new ArrayList<App> ();

            setup_ui ();
            connect_signals ();

        }

        private void setup_ui () {
            
            // Create the base container
            container = new VBox (false, 0);

            // Add top bar
            var top = new HBox (false, 10);

            // Category Switcher widget
            category_switcher = new ComboBoxText ();
            foreach (string cat in apps.keys) {
                category_switcher.append (cat, cat);
            }
            category_switcher.set_active (0);

            searchbar = new SearchBar (_("Start typing to search"));
            
            var button = new ToggleButton.with_label ("Toogle view");
            top.pack_start (button, true, true, 15);
            top.pack_start (searchbar, false, true, 0);

            // Get the current size of the view
            int width, height;
            get_size (out width, out height);
            
            // Make icon grid and populate
            grid = new Widgets.Grid (height / 180, width / 128);

            // Create the layout which works like pages
            pages = new Layout (null, null);
            pages.put (grid, 0, 0);

            // Create the page switcher
            page_switcher = new Switcher ();
            page_switcher.append ("1");
            
            // This function must be after creating the page switcher
            grid.new_page.connect (page_switcher.append);
            populate_grid ();

            grid_n_pages = new VBox (false, 0);
            grid_n_pages.pack_start (Utils.set_padding (pages, 0, 9, 0, 9), true, true, 0);
            grid_n_pages.pack_start (Utils.set_padding (page_switcher, 0, 35, 15, 35), false, true, 0);


            container.pack_start (top, false, true, 15);
            container.pack_start (grid_n_pages, true, true, 0);
            this.add (Utils.set_padding (container, 15, 15, 1, 15));

            debug ("Ui setup completed");
            button.toggled.connect (() => grid_n_pages.visible = !button.active);

        }

        private void connect_signals () {
            
            this.focus_out_event.connect ( () => {
                this.hide_slingshot(); 
                return false; 
            });
            this.draw.connect (this.draw_background);
            pages.draw.connect (this.draw_pages_background);
            searchbar.changed.connect (this.search);

            page_switcher.active_changed.connect (() => {

                if (page_switcher.active > page_switcher.old_active)
                    this.page_right (page_switcher.active - page_switcher.old_active);
                else
                    this.page_left (page_switcher.old_active - page_switcher.active);

            });

            // Auto-update settings when changed
            Slingshot.settings.changed.connect (read_settings);

        }

        private bool draw_background (Context cr) {

            Allocation size;
            get_allocation (out size);
            
            // Some (configurable?) values
            double radius = 6.0;
            double offset = 2.0;

            cr.set_antialias (Antialias.SUBPIXEL);

            cr.move_to (0 + radius, 15 + offset);
            // Create the little rounded triangle
            cr.line_to (20.0, 15.0 + offset);
            //cr.line_to (30.0, 0.0 + offset);
            cr.arc (35.0, 0.0 + offset + radius, radius - 1.0, -2.0 * Math.PI / 2.7, -7.0 * Math.PI / 3.2);
            cr.line_to (50.0, 15.0 + offset);
            // Create the rounded square
            cr.arc (0 + size.width - radius - offset, 15.0 + radius + offset, 
                         radius, Math.PI * 1.5, Math.PI * 2);
            cr.arc (0 + size.width - radius - offset, 0 + size.height - radius - offset, 
                         radius, 0, Math.PI * 0.5);
            cr.arc (0 + radius + offset, 0 + size.height - radius - offset, 
                         radius, Math.PI * 0.5, Math.PI);
            cr.arc (0 + radius + offset, 15 + radius + offset, radius, Math.PI, Math.PI * 1.5);

            cr.set_source_rgba (0.1, 0.1, 0.1, 0.7);
            cr.fill_preserve ();

            // Paint a little white border
            cr.set_source_rgba (1.0, 1.0, 1.0, 1.0);
            cr.set_line_width (1.0);
            cr.stroke ();

            return false;

        }

        private bool draw_pages_background (Widget widget, Context cr) {

            Allocation size;
            widget.get_allocation (out size);

            cr.rectangle (0, 0, size.width, size.height);

            cr.set_source_rgba (0.1, 0.1, 0.1, 0.7);
            cr.fill_preserve ();

            return false;

        }

        public override bool key_press_event (Gdk.EventKey event) {

            switch (Gdk.keyval_name (event.keyval)) {

                case "Escape":
                    hide_slingshot ();
                    return true;

                case "Ctrl_R":
                case "Ctrl_L":
                case "c":
                    Gtk.main_quit ();
                    break;

                default:
                    if (!searchbar.has_focus)
                        searchbar.grab_focus ();
                    break;

            }

            base.key_press_event (event);
            return false;

        }

        public override bool scroll_event (EventScroll event) {

            switch (event.direction.to_string ()) {
                case "GDK_SCROLL_UP":
                case "GDK_SCROLL_LEFT":
                    page_switcher.set_active (page_switcher.active - 1);
                    break;
                case "GDK_SCROLL_DOWN":
                case "GDK_SCROLL_RIGHT":
                    page_switcher.set_active (page_switcher.active + 1);
                    break;

            }

            return false;

        }

        public void hide_slingshot () {
            
            // Show the first page
            page_switcher.set_active (0);
            current_position = 0;

            hide ();

        }

        public void show_slingshot () {

            deiconify ();
            show_all ();
            grab_focus ();

        }

        private void page_left (int step = 1) {

            if (current_position < 0) {
                pages.move (grid, current_position + 5*130*step, 0);
                current_position += 5*130*step;
            }

        }

        private void page_right (int step = 1) {

            if ((- current_position) < ((grid.n_columns - 5.8)*130)) {
                pages.move (grid, current_position - 5*130*step, 0);
                current_position -= 5*130*step;
            }

        }

        private void search () {

            var text = searchbar.text.down ();

            if (text.strip () == "")
                return;

            foreach (ArrayList<App> entries in apps.values) {
                foreach (App app in entries) {
                    
                    if (text in app.name || text in app.description ||
                        text in app.exec)
                        message (app.name);

                }
            }

        }

        public void populate_grid () {

            warning ("populate_grid (): This function needs to be optimized");
            
            foreach (ArrayList<App> entries in apps.values) {
                foreach (App app in entries) {

                    var app_entry = new AppEntry (app);
                    
                    app_entry.app_launched.connect (hide_slingshot);

                    grid.append (app_entry);

                    app_entry.show_all ();

                }
            }

            debug ("Grid filled");

            page_switcher.set_active (0);

        }

        private void read_settings () {

            default_width = Slingshot.settings.width;
            default_height = Slingshot.settings.height;

        }

    }

}
