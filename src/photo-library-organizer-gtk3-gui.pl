
	
# Initialize Gtk3 before creating any widgets
use Gtk3 -init;
use Config::Tiny;     # Install the module with the command: cpan Config::Tiny


# Global file variables
my $gui_default_font = "Arial 10";

# Global GUI elements
my $window = Gtk3::Window->new('toplevel');
my $console_buffer;
my $console_view;
my $progress_bar;


# Subroutine:  create_file_chooser_frame
# Information: Creates a frame with a label, text entry, and browse button for directory selection.
# Parameters:  $_[0]: Frame title
#              $_[1]: Reference to the variable to store the selected path
#              $_[2]: Dialog action type ('select-folder' or 'open')
# Return:      Gtk3::Frame with the file chooser components
sub create_file_chooser_frame {
    my ($title, $path_ref, $action) = @_;
    
    my $frame = Gtk3::Frame->new($title);
    my $hbox = Gtk3::Box->new('horizontal', 5);
    $hbox->set_margin_start(10);
    $hbox->set_margin_end(10);
    $hbox->set_margin_top(10);
    $hbox->set_margin_bottom(10);
    $frame->add($hbox);
    
    # Create entry field
    my $entry = Gtk3::Entry->new();
    $entry->set_text($$path_ref // '');
    $entry->signal_connect('notify::text' => sub {
        $$path_ref = $entry->get_text();
    });
    $hbox->pack_start($entry, 1, 1, 0);
    
    # Create browse button
    my $browse_button = Gtk3::Button->new_with_label("Browse");
    $browse_button->signal_connect(clicked => sub {
        my $dialog = Gtk3::FileChooserDialog->new(
            "Select $title",
            $window,
            $action,
            "Cancel" => 'cancel',
            "Select" => 'accept'
        );
        
        if ($dialog->run() eq 'accept') {
            $$path_ref = $dialog->get_filename();
            $entry->set_text($$path_ref);
        }
        $dialog->destroy();
    });
    $hbox->pack_start($browse_button, 0, 0, 0);
    
    return $frame;
}

# Subroutine:  load_config
# Information: Loads configuration from INI file
# Parameters:  None
# Return:      None
sub load_config {
    my $config = Config::Tiny->read($config_file);
    if ($config) {
        $import_dir = $config->{_}->{import_dir} // '';
        $photo_library_path = $config->{_}->{photo_library_path} // '';
        $file_keyword = $config->{_}->{file_keyword} // 'IMG';
        $verbose = $config->{_}->{verbose} // $verbose_options[0];
        $auto_export_log = $config->{_}->{auto_export_log} // 1;
        $import_action = $config->{_}->{import_action} // $import_action_options[0];
        $inventory_enabled = $config->{_}->{inventory_enabled} // 1;
    }
}

# Subroutine:  save_config
# Information: Saves configuration to INI file
#              This subroutine is called when the user clicks the "Save Config" button.
# Parameters:  None
# Return:      None
sub save_config {
    my $config = Config::Tiny->new;
    $config->{_}->{import_dir} = $import_dir;
    $config->{_}->{photo_library_path} = $photo_library_path;
    $config->{_}->{file_keyword} = $file_keyword;
    $config->{_}->{verbose} = $verbose;
    $config->{_}->{auto_export_log} = $auto_export_log;
    $config->{_}->{import_action} = $import_action;
    $config->{_}->{inventory_enabled} = $inventory_enabled;
    $config->{_}->{excluded_extensions} = $excluded_extensions;
    $config->write($config_file);
}

# Subroutine:  print_to_console
# Information: Prints messages to the console with color coding
#              It classifies the message level to:
#                - VERBOSE: Optional message that users can ignore. 
#                - INFO: General information about the process that gets always printed.
#                - WARNING: Information about a non critical exception condition during the execution of the program
#                - ERROR: Information about a critical condition or exception that interfere with the correct execution of the program. 
#              This subroutine is called as replacement of print.
# Parameters:  $_[0]: Message level {VERBOSE, INFO, WARNING, ERROR}
#              $_[1]: Message text to log
# Return:      None
sub print_to_console {
    my ($message_level, $message) = @_;
    $message_level //= 'WARNING';
    
    return if ($message_level eq 'VERBOSE' && $verbose eq $verbose_options[1]);
    
    if (defined $console_buffer) {
        my $formatted_message = $message;
        $formatted_message = "$message_level: $message" if ($message_level eq 'WARNING' || $message_level eq 'ERROR');
        my $end_iter = $console_buffer->get_end_iter();
        $console_buffer->insert_with_tags_by_name($end_iter, "$formatted_message\n", $message_level);

        # Scroll to bottom
        my $mark = $console_buffer->get_insert();
        if ($console_view) {
            $console_view->scroll_mark_onscreen($mark);
        }

        Gtk3::main_iteration while Gtk3::events_pending;
    }

    $warning_counter++ if $message_level eq 'WARNING';
    $error_counter++ if $message_level eq 'ERROR';

    add_log_entry($message) if ($auto_export_log);

    print("$message_level: $message\n");
}

# Subroutine:  clean_console
# Information: Clears the console
# Parameters:  None
# Return:      None
sub clean_console {
    $console_buffer->set_text('') if defined $console_buffer;
}

# Subroutine:  warning_alert
# Information: Shows a warning dialog
# Parameters:  $_[0]: Warning message
# Return:      None
sub warning_alert {
    my ($message) = @_;
    print_to_console('WARNING', $message);
    
    if ($gui_mode) {
        my $dialog = Gtk3::MessageDialog->new(
            $window,
            'modal',
            'warning',
            'ok',
            $message
        );
        $dialog->run();
        $dialog->destroy();
    }
}

# Subroutine:  import_summary
# Information: Shows import summary dialog
# Parameters:  $_[0]: Number of files imported
#              $_[1]: Number of warnings
#              $_[2]: Number of errors
# Return:      None
sub import_summary {
    my ($files_imported, $warnings, $errors) = @_;
    
    print_to_console('INFO', "\n------------------------------------------------------");
    print_to_console('INFO', "Import process completed: $files_imported files imported, $warnings Warnings, $errors Errors");
    
    if ($gui_mode) {
        my $dialog = Gtk3::MessageDialog->new(
            $window,
            'modal',
            'info',
            'ok',
            "Import Completed: $files_imported files imported, $warnings Warnings, $errors Errors"
        );
        $dialog->run();
        $dialog->destroy();
    }
}

# Subroutine:  export_log
# Information: Exports console log to file. See verbosity levels. 
#              Subroutine gets called at the end of the import process if configuration automatically exports logs ($auto_export_log) or 
#              when "Export Log" button gets pressed. 
#              Auto export log is only available on GUI as CLI users always get events logged in console. 
# Parameters:  $_[0]: Path to the log file (optional). Launch a GUI window to select file name if not passed.
# Return:      None
sub export_log {
    my $dialog = Gtk3::FileChooserDialog->new(
        "Export Log File",
        $window,
        'save',
        "Cancel" => 'cancel',
        "Save" => 'accept'
    );
    
    $dialog->set_current_name("photo_organizer.log");
    
    if ($dialog->run() eq 'accept') {
        my $filename = $dialog->get_filename();
        if (open my $fh, '>', $filename) {
            my $text = $console_buffer->get_text(
                $console_buffer->get_start_iter(),
                $console_buffer->get_end_iter(),
                0
            );
            print $fh $text;
            close $fh;
            print_to_console('INFO', "Log exported to $filename");
        } else {
            print_to_console('ERROR', "Could not write to $filename: $!");
        }
    }
    $dialog->destroy();
}

# Subroutine:  add_log_entry
# Information: Add a new event entry to the log file.
# Parameters:  $_[0]: String with event to be added to the log file.
# Return:      None
sub add_log_entry {
    open my $fh, '>>', $log_file_path or print_to_console('ERROR', "Could not open '$_[0]' $!");
    print $fh $_[0] . "\n";
    close $fh;
}

# Subroutine:  update_progress_bar
# Information: Updates the progress bar with the given fraction and optional text
# Parameters:  $_[0]: Fraction value (0.0 to 1.0)
#              $_[1]: Optional text label
# Return:      None
sub update_progress_bar {
    my ($fraction, $text) = @_;
    $fraction //= 0;
    $text //= "";
    
    if (defined $progress_bar) {
        $progress_bar->set_fraction($fraction);
        $progress_bar->set_text($text) if $text;
        Gtk3::main_iteration while Gtk3::events_pending;
    }
}

# Subroutine:  photo_library_organizer_gui
# Information: This is the main subroutine for the GUI. It configures every element and its properties on the main window.
#              It gets called when parameter [-gui] gets passed or if no mandatory parameters where passed to the binary. 
# Parameters:  None
# Return:      None
sub photo_library_organizer_gui {

    $gui_mode = 1;
    
    # Load previously stored configuration
    load_config();

    # Create main window
    $window = Gtk3::Window->new('toplevel');
    $window->set_title("Photo Library Organizer");
    $window->set_default_size(550, 700);
    $window->set_resizable(0);
    $window->set_border_width(10);
    
    # Try to load icon
    eval {
        $window->set_icon_from_file("./icons/PhotoLibraryOrganizer.png");
    };
    
    $window->signal_connect(destroy => sub { Gtk3::main_quit(); exit(0); });

    # Create main vertical box
    my $main_vbox = Gtk3::Box->new('vertical', 10);
    $window->add($main_vbox);

    # Title Label
    my $title_label = Gtk3::Label->new("");
    $title_label->set_markup('<span font_family="Arial" weight="bold" size="20000">Photo Library Organizer</span>');
    
    $main_vbox->pack_start($title_label, 0, 0, 10);

    # Import directory frame
    my $import_frame = create_file_chooser_frame(
        "Import Directory",
        \$import_dir,
        'select-folder'
    );
    $main_vbox->pack_start($import_frame, 0, 1, 0);

    # Photo Library directory frame
    my $output_frame = create_file_chooser_frame(
        "Photo Library Directory",
        \$photo_library_path,
        'select-folder'
    );
    $main_vbox->pack_start($output_frame, 0, 1, 0);

    # Buttons and options frame
    my $button_options_hbox = Gtk3::Box->new('horizontal', 10);
    $main_vbox->pack_start($button_options_hbox, 0, 1, 0);

    # Left buttons box
    my $button_vbox = Gtk3::Box->new('vertical', 5);
    $button_options_hbox->pack_start($button_vbox, 0, 1, 0);

    my $run_button = Gtk3::Button->new_with_label("Run Importer");
    $run_button->signal_connect(clicked => \&run_photo_library_organizer);
    $button_vbox->pack_start($run_button, 1, 1, 0);

    my $save_config_button = Gtk3::Button->new_with_label("Save Config");
    $save_config_button->signal_connect(clicked => \&save_config);
    $button_vbox->pack_start($save_config_button, 1, 1, 0);

    # Right options frame
    my $options_frame = Gtk3::Frame->new("Options");
    $button_options_hbox->pack_start($options_frame, 1, 1, 0);

    my $options_vbox = Gtk3::Box->new('vertical', 5);
    $options_vbox->set_margin_start(10);
    $options_vbox->set_margin_end(10);
    $options_vbox->set_margin_top(10);
    $options_vbox->set_margin_bottom(10);
    $options_frame->add($options_vbox);

    my $options_hbox = Gtk3::Box->new('horizontal', 10);
    $options_vbox->pack_start($options_hbox, 0, 1, 0);

    my $left_options = Gtk3::Box->new('vertical', 5);
    $options_hbox->pack_start($left_options, 1, 1, 0);

    # Keyword label and entry
    my $keyword_hbox = Gtk3::Box->new('horizontal', 5);
    my $keyword_label = Gtk3::Label->new("Keyword: ");
    $keyword_hbox->pack_start($keyword_label, 0, 0, 0);
    my $keyword_entry = Gtk3::Entry->new();
    $keyword_entry->set_text($file_keyword);
    $keyword_entry->signal_connect('notify::text' => sub {
        $file_keyword = $keyword_entry->get_text();
    });
    $keyword_hbox->pack_start($keyword_entry, 0, 0, 0);
    $left_options->pack_start($keyword_hbox, 0, 0, 0);

    # Verbose combo box
    my $verbose_combo = Gtk3::ComboBoxText->new();
    foreach my $option (@verbose_options) {
        $verbose_combo->append_text($option);
    }
    $verbose_combo->signal_connect('changed' => sub {
        my $index = $verbose_combo->get_active();
        $verbose = $verbose_options[$index] if $index >= 0;
    });
    my $verbose_index = 0;
    for (my $i = 0; $i < @verbose_options; $i++) {
        if ($verbose_options[$i] eq $verbose) {
            $verbose_index = $i;
            last;
        }
    }
    $verbose_combo->set_active($verbose_index);
    $left_options->pack_start($verbose_combo, 0, 0, 0);

    # Action combo box
    my $action_combo = Gtk3::ComboBoxText->new();
    foreach my $option (@import_action_options) {
        $action_combo->append_text($option);
    }

    $action_combo->signal_connect('changed' => sub {
        my $index = $action_combo->get_active();
        $import_action = $import_action_options[$index] if $index >= 0;
    });

    my $action_index = 0;
    for (my $i = 0; $i < @import_action_options; $i++) {
        if ($import_action_options[$i] eq $import_action) {
            $action_index = $i;
            last;
        }
    }
    $action_combo->set_active($action_index);
    $left_options->pack_start($action_combo, 0, 0, 0);

    my $right_options = Gtk3::Box->new('vertical', 5);
    $options_hbox->pack_start($right_options, 1, 1, 0);

    # Export log button
    my $export_button = Gtk3::Button->new_with_label("Export Log");
    $export_button->signal_connect(clicked => \&export_log);
    $right_options->pack_start($export_button, 1, 1, 0);

    # Auto-save log checkbox
    my $auto_log_checkbox = Gtk3::CheckButton->new_with_label("Auto-Save Log");
    $auto_log_checkbox->set_active($auto_export_log);
    $auto_log_checkbox->signal_connect('toggled' => sub {
        $auto_export_log = $auto_log_checkbox->get_active();
    });
    $right_options->pack_start($auto_log_checkbox, 0, 0, 0);

    # Update inventory checkbox
    my $inventory_checkbox = Gtk3::CheckButton->new_with_label("Update Photo Inventory");
    $inventory_checkbox->set_active($inventory_enabled);
    $inventory_checkbox->signal_connect('toggled' => sub {
        $inventory_enabled = $inventory_checkbox->get_active();
    });
    $right_options->pack_start($inventory_checkbox, 0, 0, 0);

    # Console frame
    my $console_frame = Gtk3::Frame->new("Console Output");
    $main_vbox->pack_start($console_frame, 1, 1, 0);

    my $console_vbox = Gtk3::Box->new('vertical', 5);
    $console_vbox->set_margin_start(10);
    $console_vbox->set_margin_end(10);
    $console_vbox->set_margin_top(10);
    $console_vbox->set_margin_bottom(10);
    $console_frame->add($console_vbox);

    # Console text view with scroll
    $console_buffer = Gtk3::TextBuffer->new();
    
    my $info_tag = $console_buffer->create_tag('INFO', foreground => 'black');
    my $verbose_tag = $console_buffer->create_tag('VERBOSE', foreground => 'gray');
    my $warning_tag = $console_buffer->create_tag('WARNING', foreground => 'orange');
    my $error_tag = $console_buffer->create_tag('ERROR', foreground => 'red');

    $console_view = Gtk3::TextView->new_with_buffer($console_buffer);
    $console_view->set_editable(0);
    $console_view->set_wrap_mode('none');
    $console_view->set_monospace(0);

    my $scrolled_window = Gtk3::ScrolledWindow->new();
    $scrolled_window->set_policy('automatic', 'automatic');
    $scrolled_window->set_min_content_height(250);
    $scrolled_window->add($console_view);
    $console_vbox->pack_start($scrolled_window, 1, 1, 0);

    # Progress bar
    $progress_bar = Gtk3::ProgressBar->new();
    $progress_bar->set_show_text(0);
    $console_vbox->pack_start($progress_bar, 0, 1, 0);

    # Show all widgets
    $window->show_all();

    # Run the GTK main loop
    Gtk3::main();
}

# Return True
1;