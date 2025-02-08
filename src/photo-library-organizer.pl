#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;
use File::Copy;
use File::Find;
use File::Path qw(make_path);
use File::stat;
use Image::ExifTool qw(:Public); # Install the module with the command: cpan Image::ExifTool
use Digest::CRC qw(crc32);       # Install the module with the command: cpan Digest::CRC
use File::Slurp qw(read_file);
use Getopt::Long;
use DateTime;
require "./src/photo-library-organizer-gui.pl";

# Global variables
my $import_counter = 0;
my $process_running = 0;
our $warning_counter = 0;
our $error_counter = 0;
our $progress_value = 0;

my @months_name = ('January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December');
my @inventory_entries = ('Imported Date', 'File Path', 'File CRC32', 'File Size', 'File Type', 'DateTimeOriginal', 'Make', 'Model', 'Image Size', 'Megapixels', 
                         'Focal Length', 'Exposure Time', 'Aperture (f)', 'ISO', 'LensInfo', 'Flash', 'GPS Latitude', 'GPS Longitude');
our @verbose_options = ("All Events", "Warnings & Errors");
our @import_action_options = ("Copy files", "Move files"); 
our $auto_export_log;
our $inventory_enabled;
our $gui_mode = 0;
our $file_keyword = 'IMG';
our $verbose = $verbose_options[1];
our $import_action = $import_action_options[0];
our $log_file_path;
my @files_to_import;

# -------------------------------------------------------------------------------
# Program entry
# -------------------------------------------------------------------------------

# Parse command-line arguments 
GetOptions( 'k=s' => \$file_keyword, 
            'gui' => \&photo_library_organizer_gui, 
            'mv' => sub { $import_action = $import_action_options[1]}, 
            'i' => sub { $inventory_enabled = 1;}, 
            'v' => sub { $verbose = 1;}, 
            'l' => sub { $auto_export_log = 1;}, 
            'h' => \&show_help
) or show_help();

our ($import_dir, $photo_library_path) = @ARGV;

# Check for minimum mandatory arguments for CLI
if (defined $import_dir && defined $photo_library_path) {
    run_photo_library_organizer();
}
else{ 
    # Run GUI if no arguments are provided
    photo_library_organizer_gui();
}

# -------------------------------------------------------------------------------

# Subroutine:  show_help
# Information: Subroutine to print help message and information about the parameters
#              This subroutines is called when help argument [-h] is passed or when invalid usage gets detected.
#              Program execution is terminated
# Parameters:  None
# Return:      None
sub show_help {
    print "\nPhoto Library Organizer\n\n";
    print "Usage: $0 <import_dir> <photo_library_path> [-k <file_keyword>] [-v] [-mv] [-gui]\n";
    print "Options:\n";
    print "  <import_dir>          : (Mandatory if CLI) Path of files to import.\n";
    print "  <photo_library_path>  : (Mandatory if CLI) Path of your photo library.\n";
    print "  -k <file_keyword>     : (Optional. Default: IMG) Keyword to be added at the begining of file name.\n";
    print "  -gui                  : Run the GUI version of the program\n";
    print "  -mv                   : Move files to library. If not selected files are copied. \n";
    print "  -i                    : Update Photo Inventory; Generates a CSV file with an inventory of all imported assests. \n";
    print "  -v                    : Verbose mode. \n";
    print "  -l                    : Store log file. Details of log file are impacted by verbose mode selected. \n";
    print "  -h                    : Show this help message\n";
    print "\n";
    exit;
}

# Subroutine:   calculate_file_crc32
# Information:  Subroutine to calculate the CRC32 checksum of a file in binary mode. 
# Parameters:   $_[0]: Path to the file
# Return:       CRC32 of file in hexadecimal format
sub calculate_file_crc32 {
    my $data = read_file( $_[0], binmode => ':raw');
    my $crcDigest = Digest::CRC->new(type => 'crc32');
    $crcDigest->add($data);
    return $crcDigest->hexdigest;
}

# Subroutine:  add_inventory_entry
# Information: Subroutine to add a new entry to the inventory/CSV file. Each entry corresponds to a file imported into the library.
#              It is responsability of the caller to ensure that structure of the string matches the CSV header defined in @inventory_entries
# Parameters:  $_[0]: Path to the inventory/CSV file
#              $_[1]: String to be added to the inventory/CSV file
# Return:      None
sub add_inventory_entry {

    # Initialize CSV file if not exists
    if (!-e $_[0]) {
        open my $fh, '>', File::Spec->catfile($photo_library_path, 'inventory.csv') or print_to_console('ERROR', "Could not open '$_[0]' $!");
        print $fh join(", ", @inventory_entries) . "\n";
        close $fh;
    }

    # Add entry to CSV file
    open my $fh, '>>', $_[0] or print_to_console('ERROR', "Could not open '$_[0]' $!");
    print $fh $_[1];
    close $fh;
}
# Subroutine:  index_files_to_import
# Information: Subroutine to find and index all files to import. 
#              This subroutine is called by the find function. It validates the file before doing the import process.
# Parameters:  None
# Return:      None
sub index_files_to_import {
    
    return if -d;
    my $file_path = "$File::Find::name";
    my ($file_name, $file_dir, $file_ext) = fileparse($file_path, qr/\.[^.]*/);
    
    # Process only files with supported extensions.
    if ((!defined Image::ExifTool::GetFileType($file_path)) or (!-e $file_path)) {
        print_to_console('WARNING', "Unsupported file: '$file_path'");
        return;
    }

    push @files_to_import, $file_path;
}

# Subroutine:  process_file
# Information: Subroutine to process each of the files that are found in the import directory.
#              This is the main subroutine of the program. It is called by the find function.
#              This subroutine validates the file, calculates its CRC32 checksum, extracts metadata, and copy/moves the file to the library.
# Parameters:  None
# Return:      None
sub process_file {

    my $file_path = $_[0];
    my ($file_name, $file_dir, $file_ext) = fileparse($file_path, qr/\.[^.]*/);
      

    # Calculate CRC of the file    
    my $file_crc = calculate_file_crc32($file_path);

    # Extract metadata from the file
    my $exifTool = new Image::ExifTool;
    $exifTool->ExtractInfo($file_path);
    my $date = $exifTool->GetValue('CreateDate', 'PrintConv')        || 
                $exifTool->GetValue('DateTimeOriginal', 'PrintConv') ||
                $exifTool->GetValue('FileModifyDate', 'PrintConv')   ||
                $exifTool->GetValue('FileCreateDate', 'PrintConv');

    # Parse extracted date to compose the new file name and path
    my ($year, $month, $day, $hour, $minute, $second) = $date =~ /(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})/;
    my $new_file_dir = "${photo_library_path}/${year}/${month}_${months_name[$month - 1]}/";
    my $new_file_name = "${file_keyword}_${year}${month}${day}_${hour}${minute}${second}_${file_crc}${file_ext}";
    my $new_file_path = $new_file_dir . $new_file_name;

    # Create the directory if it doesn't exist
    make_path($new_file_dir) unless -d $new_file_dir;

    # Import file
    print_to_console('WARNING', "'$file_path' already in library. CRC32 ('${file_crc}') matched with file '$new_file_path'. File not imported.") && return if -e $new_file_path;
    if ($import_action eq $import_action_options[1]) {
        move($file_path, $new_file_path)? $import_counter++ : print_to_console('ERROR', "'$file_path' move failed: $!" && return);
    } else {
        copy($file_path, $new_file_path)? $import_counter++ : print_to_console('ERROR', "'$file_path' copy failed: $!" && return);
    }
    print_to_console('VERBOSE', "[$progress_value%] Import File:'$file_path' to '$new_file_path'");
    
    # add to file inventory
     if ($inventory_enabled) {

        (my $flash_info = $exifTool->GetValue('Flash', 'PrintConv') || ' ')=~ s/[,]/;/g; # Replace ',' with ';' in flash value
        (my $extension = $file_ext) =~ s/[^.]*\.//g; # Remove '.' from file extension
        my $import_date = DateTime->now->strftime('%Y:%m:%d %H:%M:%S ') . DateTime->now->time_zone->name;
        # Write entry to inventory
        add_inventory_entry("$photo_library_path/inventory.csv", 
                           "$import_date, " .
                           "$new_file_path, " .
                           "$file_crc, " .
                           ($exifTool->GetValue('FileSize', 'PrintConv') || ' ') . ', ' .
                           ($exifTool->GetValue('FileTypeExtension', 'PrintConv') || ' ') . ', ' .
                           "$date, " .
                           ($exifTool->GetValue('Make', 'PrintConv') || ' ') . ', ' .
                           ($exifTool->GetValue('Model', 'PrintConv') || ' ') . ', ' .
                           ($exifTool->GetValue('ImageSize', 'PrintConv') || ' ') . ', ' .
                           ($exifTool->GetValue('Megapixels', 'PrintConv') || ' ') . ', ' .
                           ($exifTool->GetValue('FocalLength', 'PrintConv') || ' ') . ', ' .
                           ($exifTool->GetValue('ExposureTime', 'PrintConv') || ' ') . ', ' .
                           ($exifTool->GetValue('FNumber', 'PrintConv') || ' ') . ', ' .
                           ($exifTool->GetValue('ISO', 'PrintConv') || ' ') . ', ' .
                           ($exifTool->GetValue('LensInfo', 'PrintConv') || ' ') . ', ' .
                           "$flash_info, " .
                           ($exifTool->GetValue('GPSLatitude', 'PrintConv') || ' ') . ', ' .
                           ($exifTool->GetValue('GPSLongitude', 'PrintConv') || ' ') . "\n");
     }
}

# Subroutine:  __DIE__
# Information: Custom error handling subroutine. Routine gets executed when script is terminated due to a fatal error. 
# Parameters:  None
# Return:      None
$SIG{__DIE__} = sub { 
    print_to_console('ERROR',"An error occurred: @_");
    exit(1); 
};

# Subroutine:  run_photo_library_organizer
# Information: Main subroutine - equivalent to main function. Initializes global variables and triggers the file import and processing.
#              Stores log information after the import process is completed. 
#              This subroutine is called by the GUI when "Run" button gets pressed and by the CLI when correct arguments are provided.
# Parameters:  None
# Return:      None
sub run_photo_library_organizer {

    # Check if process is already running
    warning_alert("Process is already running. Wait until it finishes.") && return if $process_running;

    # start process
    $process_running = 1;
    clean_console();

    # Reset counters
    $import_counter = 0;
    $warning_counter = 0;
    $error_counter = 0;

    # Validate Paths
    print_to_console('ERROR', "Invalid import path: $import_dir ") && show_help() unless defined $import_dir;
    print_to_console('ERROR', "Invalid Photo Library path: $photo_library_path") && show_help() unless defined $photo_library_path;
    
    # Set log file name
    if ($auto_export_log) {
        my $import_date_subfix = DateTime->now->strftime('%Y-%m-%d_%H-%M-%S_') . DateTime->now->time_zone->name; 
        $log_file_path = "$photo_library_path/log/import-$import_date_subfix.log";
        make_path("$photo_library_path/log") unless -d "$photo_library_path/log";
    }

    print_to_console('INFO', "------------------------------------------------------");
    print_to_console('INFO', "   Running Photo Library Organizer"                    );
    print_to_console('INFO', "------------------------------------------------------");
    print_to_console('INFO', " Import Directory: $import_dir");
    print_to_console('INFO', " Photo Library Directory: $photo_library_path");
    print_to_console('INFO', " Options:");
    print_to_console('INFO', "      - File Keyword: $file_keyword");
    print_to_console('INFO', "      - Import action: $import_action");
    print_to_console('INFO', "      - Verbose: $verbose");
    print_to_console('INFO', "      - Update inventory: " . ($inventory_enabled? "Yes" : "No"));
    print_to_console('INFO', "      - Import Log: " . ($auto_export_log? "$log_file_path" : "Not generated"));
    print_to_console('INFO', "------------------------------------------------------\n");

    # Index files to import
    find(\&index_files_to_import, $import_dir); 

    my $total_files = scalar @files_to_import;
    my $processed_files = 0;

    # Import files 
    foreach my $file (@files_to_import) {
        $processed_files++;
        $progress_value = sprintf("%.0f", ($processed_files / scalar @files_to_import) * 100);
        process_file($file);
    }

    # Print import summary
    import_summary($import_counter, $warning_counter, $error_counter);

    # End process
    $process_running = 0;
    $progress_value = 0;
}


