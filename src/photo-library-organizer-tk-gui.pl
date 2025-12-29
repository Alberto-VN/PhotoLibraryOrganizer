use Tk;               # cpanm https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/patched_cpan_modules/Tk-804.036_001.tar.gz
use Tk::BrowseEntry;
use Tk::LabFrame;
use Tk::ProgressBar;
use Config::Tiny;     # Install the module with the command: cpan Config::Tiny

# Global file variables
my $gui_default_font = "{Arial} 10";

# Global GUI elements
my $mw = MainWindow->new;
my $console;
my $progress_bar_label_text;
my $gui_mode = 0;

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
        $verbose_level = $config->{_}->{verbose_level} // $verbose_level;
        $auto_export_log = $config->{_}->{auto_export_log} // 1;
        $import_action = $config->{_}->{import_action} // $import_action_options[0];
        $inventory_enabled = $config->{_}->{inventory_enabled} // 1;
        $excluded_extensions = $config->{_}->{excluded_extensions} // $excluded_extensions;
        print_to_console('DEBUG', "Configuration loaded from $config_file");
    }
    else
    {
        print_to_console('DEBUG', "Failed to load configuration");
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
    $config->{_}->{verbose_level} = $verbose_level;
    $config->{_}->{auto_export_log} = $auto_export_log;
    $config->{_}->{import_action} = $import_action;
    $config->{_}->{inventory_enabled} = $inventory_enabled;
    $config->{_}->{excluded_extensions} = $excluded_extensions;
    $config->write($config_file);
    print_to_console('DEBUG', "Configuration saved to $config_file");
}

# Subroutine:  print_to_console
# Information: Prints messages to the console with color coding
#              It classifies the message level to:
#                - INFO: General information about the process that gets always printed.
#                - VERBOSE: Additional information about import process. 
#                - DEBUG: Detailed debug information for troubleshooting.
#                - WARNING: Information about a non critical exception condition during the execution of the program
#                - ERROR: Information about a critical condition or exception that interfere with the correct execution of the program. 
#              This subroutine is called as replacement of print.
# Parameters:  $_[0]: Message level {VERBOSE, INFO, WARNING, ERROR}
#              $_[1]: Message text to log
# Return:      None
sub print_to_console {

    my ($message_level, $message) = @_;
    my $console_print = 1;
    $message_level //= 'WARNING';
    $message = "$message_level: $message" if ($message_level ne 'INFO' && $message_level ne 'VERBOSE');

    # Update Error counters
    $warning_counter++ if $message_level eq 'WARNING';
    $error_counter++ if $message_level eq 'ERROR';

    # Execute the filter based on the current verbose level
    # 0  -> Info |                                      -> Log and console
    # 1  -> Info | Warnings & Errors |                  -> Log and console
    # 2  -> Info | Warnings & Errors | Verbose          -> Log and console
    # 3  -> Info | Warnings & Errors | Verbose | Debug  -> Log file only (suppress console output)
    # 4  -> Info | Warnings & Errors | Verbose | Debug  -> Log and console
    return if ($message_level eq 'WARNING' || $message_level eq 'ERROR') && ($verbose_level == 0);
    return if $message_level eq 'VERBOSE' && ($verbose_level <= 1);
    return if $message_level eq 'DEBUG' && ($verbose_level <= 2);

    # Suppress console output for DEBUG messages at level 3
    $console_print = 0 if ($message_level eq 'DEBUG' && $verbose_level == 3);

    if ( defined $console && $console_print) {
        $console->configure(-state => 'normal');
        $console->insert('end', "$message\n", $message_level);
        $console->see('end');
        $console->update;  # Force the GUI to refresh immediately
        $console->configure(-state => 'disabled');
    }

    # Add to log file
    add_log_entry("$message") if ($auto_export_log);

    # Print to standard output if in CLI mode
    print("$message\n");
}

# Subroutine:  clean_console
# Information: Clears the console
# Parameters:  None
# Return:      None
sub clean_console {

    if ( defined $console ) {
        $console->configure(-state => 'normal');
        $console->delete('1.0', 'end');
        $console->update;  # Force the GUI to refresh immediately
        $console->configure(-state => 'disabled');
    }
}

# Subroutine:  warning_alert
# Information: Shows a warning dialog
# Parameters:  $_[0]: Warning message
# Return:      None
sub warning_alert {

    print_to_console('WARNING', "$_[0]");
    $mw->messageBox(-message => "$_[0]", 
                    -type => "ok", 
                    -icon => "warning", 
                    -title => "Warning") if $gui_mode;
}

# Subroutine:  import_summary
# Information: Shows import summary dialog
# Parameters:  None
# Return:      None
sub import_summary {
    
    print_to_console('INFO', "\n------------------------------------------------------");
    print_to_console('INFO', "Import process completed: \n");
    print_to_console('INFO', "Assets imported: $import_counter / $total_files");
    print_to_console('INFO', "Duplicates found: $duplicated_counter");
    print_to_console('INFO', "Not supported/excluded: $not_imported_counter");
    print_to_console('INFO', "Warnings: $warning_counter");
    print_to_console('INFO', "Errors: $error_counter");
    print_to_console('INFO', "------------------------------------------------------\n");
    
    if ($gui_mode) {
      $mw->messageBox(-message => "\nImport Completed:\n\n $import_counter/$total_files files imported, $duplicated_counter Duplicates found, $warning_counter Warnings, $error_counter Errors\nSee log for details", 
                      -type => "ok", 
                      -icon => "info", 
                      -title => "Import Completed");
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
    my $log_file = $_[0] || $mw->getSaveFile(-defaultextension => ".log", -filetypes => [['Log file', '.log'], ['Text Files', '.txt'], ['All Files', '*']]) ;
    
    if ($log_file) {
        open my $fh, '>', $log_file or do {
            print_to_console('ERROR', "Failed to open file for writing: $!");
            return;
        };
        print $fh $console->get('1.0', 'end');
        close $fh;
        print_to_console('INFO', "\nLog exported to $log_file");
    }
}

# Subroutine:  add_log_entry
# Information: Add a new event entry to the log file.
# Parameters:  $_[0]: String with event to be added to the log file.
# Return:      None
sub add_log_entry {

    if (defined $log_file_path) {
        open my $fh, '>>', $log_file_path or print_to_console('ERROR', "Could not open '$_[0]' $!");
        print $fh $_[0] . "\n";
        close $fh;
    }

}


# Subroutine:  update_progress_bar
# Information: Updates the progress bar with the given fraction and optional text
# Parameters:  $_[0]: Fraction value (0.0 to 1.0)
#              $_[1]: Optional text label
# Return:      None
sub update_progress_bar {
  $progress_bar_label_text = $_[1] if defined $_[1];
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

    # Routine to close the GUI
    $mw->protocol('WM_DELETE_WINDOW' => sub {$mw->destroy;
                                             exit; });

    #########################  Main Windows ###########################
    $mw->title("Photo Library Organizer");
    if ($^O eq 'linux') {
        $mw->geometry("1100x1400");
    } else {
        $mw->iconbitmap("./icons/PhotoLibraryOrganizer.ico");
        $mw->geometry("550x700");
    }
    $mw->resizable(0, 0);

    #########################  Title Label ############################
    my $title_label = $mw->Label(-text => "Photo Library Organizer", 
                                 -font => "{Arial} 20 {bold}")->pack(-side => 'top', -pady => 10);

    ######################### Import directory #########################
    my $input_frame = $mw->LabFrame(-label => "Import Directory", 
                                    -font => $gui_default_font, 
                                    -labelside => 'acrosstop')->pack(-side => 'top',  -fill => 'x', 
                                                                     -padx => 10, -pady => 5);
    $input_frame->Entry(-textvariable => \$import_dir, 
                        -font => $gui_default_font, 
                        -width => 60)->pack(-side => 'left', 
                                            -padx => 5, -pady => 5);
    $input_frame->Button(-text => "Browse", 
                         -font => $gui_default_font, 
                          -width => 8, -height => 1,
                         -command => sub { $import_dir = $mw->chooseDirectory; })->pack(-side => 'left', 
                                                                                        -padx => 5, -pady => 5);
                                                                                        
    ################# Photo Library directory #########################
    my $output_frame = $mw->LabFrame(-label => "Photo Library Directory", 
                                     -font => $gui_default_font, 
                                     -labelside => 'acrosstop')->pack(-side => 'top', -fill => 'x', 
                                                                      -padx => 10, -pady => 5);
    $output_frame->Entry(-textvariable => \$photo_library_path, 
                         -font => $gui_default_font, 
                         -width => 60)->pack(-side => 'left', 
                                             -padx => 5, -pady => 5);
    $output_frame->Button(-text => "Browse", 
                          -font => $gui_default_font, 
                          -width => 8, -height => 1,
                          -command => sub { $photo_library_path = $mw->chooseDirectory; })->pack(-side => 'left', 
                                                                                                 -padx => 5, -pady => 5);

    ########################## Action Buttons ######################
    my $button_options_frame = $mw->Frame()->pack(-side => 'top', -fill => 'x',
                                                  -padx => 10, -pady => 0);

    my $button_frame = $button_options_frame->Frame()->pack(-side => 'left', -fill => 'x',
                                                            -padx => 2, -pady => 5);
    
    $button_frame->Button(-text => "Run Importer", 
                          -font => $gui_default_font, 
                          -width => 13, -height => 2,
                          -command => \&run_photo_library_organizer)->pack(-side => 'top',   -expand => 1,
                                                                           -padx => 5, -pady => 5);
    # $button_frame->Button(-text => "More Options", 
    #                                         -font => $gui_default_font, 
    #                                         -width => 13, -height => 2,
    #                                         -command => \&toggle_console_log)->pack(-side => 'left',   -expand => 1,
    #                                                                                 -padx => 5, -pady => 5);
    $button_frame->Button(-text => "Save Config", 
                          -font => $gui_default_font, 
                          -width => 13, -height => 2,
                          -command => \&save_config)->pack(-side => 'top',   -expand => 1,
                                                           -padx => 5, -pady => 5);

    # $button_frame->Button(-text => "Close", 
    #                       -font => $gui_default_font, 
    #                       -width => 13, -height => 2,
    #                       -command => \&exit)->pack(-side => 'top',   -expand => 1,
    #                                                        -padx => 5, -pady => 5);

    ########################## Options #######################

    my $options_frame = $button_options_frame->LabFrame(-label => "Options", 
                                      -font => $gui_default_font, 
                                      -labelside => 'acrosstop')->pack(-side => 'left', -fill => 'x',
                                                                       -padx => 2, -pady => 0, -expand => 1);
    my $options_left_frame = $options_frame->Frame()->pack(-side => 'left', -fill => 'both', -expand => 1);
    my $options_right_frame = $options_frame->Frame()->pack(-side => 'left', -fill => 'both', -expand => 1);

    # Image keyword
    my $options_image_keyword_frame = $options_left_frame->Frame()->pack(-side => 'top', -anchor => 'w',);
    $options_image_keyword_frame->Label(-text => "Keyword: ", 
                          -font => $gui_default_font)->pack(-side => 'left',
                                                            -padx => 5, -pady => 5);
    $options_image_keyword_frame->Entry(-textvariable => \$file_keyword, 
                          -font => $gui_default_font, 
                          -width => 8)->pack(-side => 'left',
                                              -padx => 5, -pady => 5);

    my $verbose_value = $verbose_options[$verbose_level];
    $options_left_frame->BrowseEntry( -label => "Verbose: ", 
                                       -font => $gui_default_font, 
                                       -variable => \$verbose_value,
                                       -choices => \@verbose_options,
                                       -autolimitheight => 1,
                                       -width => 15,
                                       -state => 'readonly',
                                       -browse2cmd => sub { 
                                            my ($widget, $index, $value) = @_; 
                                            $verbose_level = $index;
                                        })->pack(-side => 'top', -anchor => 'w',
                                                 -padx => 5, -pady => 5);

    $options_left_frame->BrowseEntry( -label => "  Action: ", 
                                       -font => $gui_default_font, 
                                       -variable => \$import_action,
                                       -choices => \@import_action_options,
                                       -autolimitheight => 1,
                                       -width => 15,
                                       -state => 'readonly')->pack(-side => 'top', -anchor => 'w',
                                                                   -padx => 5, -pady => 5);

    # Export log button
    $options_right_frame->Button(-text => "Export Log", 
                          -font => $gui_default_font, 
                          -width => 13, -height => 2,
                          -command => \&export_log )->pack(-side => 'top', 
                                                           -padx => 5, -pady => 5);
    $options_right_frame->Checkbutton( -text => "Auto-Save Log", 
                                         -variable => \$auto_export_log, 
                                         -font => $gui_default_font)->pack(-side => 'top', -anchor => 'w');
    $options_right_frame->Checkbutton( -text => "Update Photo Inventory", 
                                         -variable => \$inventory_enabled, 
                                         -font => $gui_default_font)->pack(-side => 'top', -anchor => 'w');
    ########################## Console #######################
    my $console_frame = $mw->LabFrame(-label => "Console Output", 
                                      -font => $gui_default_font, 
                                      -labelside => 'acrosstop')->pack(-side => 'top', -fill => 'both',
                                                                       -padx => 10, -pady => 10,
                                                                       -expand => 1);
    $console = $console_frame->Scrolled('Text', -wrap => 'none', 
                                        -font => $gui_default_font, 
                                        -height => 10, 
                                        -scrollbars => 'osoe',
                                        -state => 'disabled')->pack(-side => 'top', 
                                                                    -fill => 'both', 
                                                                    -expand => 1);
    my $progress_bar_label = $console_frame->Label(-text => "0% Completed", 
                                                   -textvariable => \$progress_bar_label_text,
                                                   -font => $gui_default_font)->pack(-side => 'top', 
                                                                                    -pady => 5);
    my $progress_bar = $console_frame->ProgressBar(-width => 5, 
                                                  -length => 515, 
                                                  -from => 0, 
                                                  -to => 100, 
                                                  -blocks => 1,
                                                  -variable  => \$progress_value,
                                                  -colors => [0, 'green'])->pack(-side => 'top');
    ###################### Console Color code ###################               
    $console->tagConfigure('ERROR', -foreground => 'red');
    $console->tagConfigure('WARNING', -foreground => 'orange');
    $console->tagConfigure('INFO', -foreground => 'black');  
    $console->tagConfigure('VERBOSE', -foreground => 'black');  


    MainLoop;
}

# Return True
1;