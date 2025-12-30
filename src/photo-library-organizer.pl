#!/usr/bin/perl.
use strict;
use warnings;
use File::Basename;
use File::Copy;
use File::Find;
use File::Path qw(make_path);
use File::stat;
use Image::ExifTool qw(:Public);
use Digest::CRC qw(crc32);
use File::Slurp qw(read_file);
use POSIX qw(strftime);
use Getopt::Long;
use DateTime;
use JSON;
use LWP::UserAgent;

# Global variables
my $process_running = 0;
our $log_file_path;
my @files_to_import;
my %location_cache;
our $auto_export_log;
our $inventory_enabled;

# Counters
our $import_counter = 0;
our $total_files = 0;
our $warning_counter = 0;
our $duplicated_counter = 0;    
our $not_imported_counter = 0;
our $error_counter = 0;
our $progress_value = 0;

 # Verbose Levels:
 # 0  -> Info |                                      -> Log and console
 # 1  -> Info | Warnings & Errors |                  -> Log and console
 # 2  -> Info | Warnings & Errors | Verbose          -> Log and console
 # 3  -> Info | Warnings & Errors | Verbose | Debug  -> Log file only  
 # 4  -> Info | Warnings & Errors | Verbose | Debug  -> Log and console
our $verbose_level = 2;
our @verbose_options = ("Info", "Warnings & Errors", "All Events", "Debug - Log", "Debug - Console");
our @import_action_options = ("Copy files", "Move files", "Dry Run", "File validation"); 
my @months_name = ('January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December');

our $file_keyword = 'IMG';
our $import_action = 'Copy files';

our $config_file = './data/Photo-Library-Organizer.ini';
my $location_cache_file = "./data/locations-cache.json";

# Prefered date tags for each file format. 
our @prefered_date_tags = (['mov', 'CreationDate'],
                           ['*', 'CreateDate'],
                           ['*', 'DateTimeOriginal'],
                           ['*', 'FileModifyDate'],
                           ['*', 'FileCreateDate']);

# Files extensions excluded from import.
our $excluded_extensions = qr/\.(csv|db|doc|docx|pdf|xlsx|zip|7z)$/i; 


# Load GUI module conditionally
if ($^O eq 'linux') {
    require "./src/photo-library-organizer-gtk3-gui.pl";
} elsif ($^O eq 'MSWin32') {
    require "./src/photo-library-organizer-tk-gui.pl";
}

# -------------------------------------------------------------------------------
# Program entry
# -------------------------------------------------------------------------------

# Load location cache from file to ram if it exists
load_location_cache();

# Parse command-line arguments 
GetOptions( 'k=s' => \$file_keyword, 
            'gui' => \&photo_library_organizer_gui, 
            'cp' => sub { $import_action = 'Copy files'}, 
            'mv' => sub { $import_action = 'Move files'},
            'dry-run' => sub { $import_action = 'Dry Run'}, 
            'validation' => sub { $import_action = 'File validation'}, 
            'i' => sub { $inventory_enabled = 1;}, 
            'v:i' => \$verbose_level, 
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
    print "  -cp                   : Copy files to library. This is the default action. \n";
    print "  -dry-run              : Dry-run mode. No files are copied or moved. Only validation and file path generation is performed. \n";
    print "  -validation           : File validation mode. Only file validation to inspect compatible files is performed. No files are copied or moved. \n";
    print "  -inventory            : Update Photo Inventory; Generates a CSV file with an inventory of all imported assests. \n";
    print "  -v <level>            : Verbose level. \n";
    print "                          Levels: \n";
    print "                                 '0' - Info |                                      -> Log and console \n";
    print "                                 '1' - Info | Warnings & Errors |                  -> Log and console \n";
    print "                                 '2' - Info | Warnings & Errors | Verbose          -> Log and console \n";
    print "                                 '3' - Info | Warnings & Errors | Verbose | Debug  -> Log file only   \n";
    print "                                 '4' - Info | Warnings & Errors | Verbose | Debug  -> Log and console \n";
    print "  -log                  : Store log file. Details of log file are impacted by verbose mode selected. \n";
    print "  -h                    : Show this help message\n";
    print "\n";
    exit;
}

# Subroutine:   calculate_file_crc32
# Information:  Subroutine to calculate the CRC32 checksum of a file in binary mode. 
# Parameters:   $_[0]: Path to the file
# Return:       CRC32 of file in hexadecimal format
sub calculate_file_crc32 {
    
    my $crcDigest = Digest::CRC->new(type => 'crc32');
    my $chunk_size = 102400000; # Read file in 100Mb chunks
    my $buffer;

    open my $fh, '<:raw', $_[0] or print_to_console('ERROR', "Cannot open file $_[0]: $!");
    # Read and add data in chunks
    while (read($fh, $buffer, $chunk_size)) {
        $crcDigest->add($buffer);
    }
    close $fh;

    return $crcDigest->hexdigest;
}

# Subroutine:  load_location_cache
# Information: Subroutine to load locations cache data from JSON file into %location_cache hash.
# Parameters:  None
# Return:      None
sub load_location_cache {

  if (-e $location_cache_file) {

      print_to_console('DEBUG', "Loading location cache from $location_cache_file");
      eval {
          my $json_text = read_file($location_cache_file);
          %location_cache = %{ decode_json($json_text) };
    };
    print_to_console('ERROR', "Failed to load location cache: $@") if $@;
  }
}

# Subroutine:  store_location_cache
# Information: Subroutine to store locations cache data from %location_cache hash into JSON file.
# Parameters:  None
# Return:      None
sub store_location_cache {
    my $json = JSON->new->utf8->pretty->encode(\%location_cache); 
    open my $fh, '>', $location_cache_file  or print_to_console('ERROR', "Cannot write file: $!"); 
    print $fh $json; 
    close $fh;
}

sub convert_cordenates_to_decimal {
    my ($coordinate_string) = @_;
    my $latitude = undef;
    my $longitude = undef;

    # Extract latitude and longitude components using regex
    if ($coordinate_string =~ /(\d+)\s*deg\s*(\d+)'?\s*(\d+(?:\.\d+)?)"?\s*([NS])\s*,\s*(\d+)\s*deg\s*(\d+)'?\s*(\d+(?:\.\d+)?)"?\s*([EW])/) {
        my ($lat_d, $lat_m, $lat_s, $lat_dir, $lon_d, $lon_m, $lon_s, $lon_dir) = ($1, $2, $3, $4, $5, $6, $7, $8);

        # Convert DMS to decimal degrees
        $latitude  = $lat_d + ($lat_m / 60) + ($lat_s / 3600);
        $longitude = $lon_d + ($lon_m / 60) + ($lon_s / 3600);

        # Adjust for direction (N/S and E/W)
        $latitude  *= -1 if $lat_dir eq 'S';
        $longitude *= -1 if $lon_dir eq 'W';
    }

    return ($latitude, $longitude);
}

# Subroutine:  decode_location
# Information: Subroutine to get detailed location information (city, state, country) from latitude and longitude using Nominatim API.
# Parameters:  $_[0]: Latitude
#              $_[1]: Longitude
# Return:      Detailed location string
sub decode_location {

  my ($latitude, $longitude) = @_;

  # Round latitude and longitude to 3 decimal places. This provides an accuracy of about 111 meters at the equator. Reduces API calls while improve speed.
  $latitude = sprintf("%.3f", $latitude);
  $longitude = sprintf("%.3f", $longitude);
  my %location;
  $location{display_name} = ' ';
  $location{address}{country} =  ' ';

  # Check if location is already in cache
  if (exists $location_cache{"$latitude,$longitude"}{display_name} && 
      exists $location_cache{"$latitude,$longitude"}{address}) {
      $location{display_name} = $location_cache{"$latitude,$longitude"}{display_name};
      $location{address} = $location_cache{"$latitude,$longitude"}{address};
      return %location;
  }
  else {
      # Fetch location data from Nominatim API
      my $ua = LWP::UserAgent->new; 
      $ua->agent("PhotoLibraryOrganizer/v1.0"); # REQUIRED by Nominatim 
      my $nominatim_url = "https://nominatim.openstreetmap.org/reverse?lat=$latitude&lon=$longitude&zoom=15&format=jsonv2&accept-language=en";
      my $location_data = $ua->get($nominatim_url);

      print_to_console('DEBUG', "Fetching location data for coordinates: $latitude, $longitude from Nominatim API");

      if (!$location_data->is_success) {
          print_to_console('ERROR', "Failed to fetch location data: $@");
          return %location;
      } 
      else {

          # Decode JSON response
          my $raw = $location_data->content; 
          $raw =~ s/^\xEF\xBB\xBF//; # Remove BOM if present
          $raw =~ s/^\s+//; # Remove leading whitespace (spaces, tabs, newlines)
          my $location_info = eval { decode_json($raw) };

          if ($@) { 
            print_to_console('ERROR', "Failed to parse JSON: $@\n");
            return %location;
          } 
          else {

            # Store location info in cache
            $location_cache{"$latitude,$longitude"}{display_name} = $location_info->{display_name};
            $location_cache{"$latitude,$longitude"}{address} = $location_info->{address};
            print_to_console('DEBUG', "Location fetched: $location_info->{display_name}");
            store_location_cache();

            # set return values
            $location{display_name} = $location_info->{display_name};
            $location{address} = $location_info->{address};
         }
      }

  }

  return %location;
}

# Subroutine:  read_file_metadata
# Information: Subroutine to find and index all files to import. 
#              This subroutine is called by the find function. It validates the file before doing the import process.
# Parameters:  %_ : Hash reference containing Key: 'ImportPath' with path of file to import. 
# Return:      None
sub read_file_metadata 
{
    my $file_path = $_[0];
    my %file_metadata;

    my $exifTool = new Image::ExifTool;
    $exifTool->ExtractInfo($file_path);
    
    print_to_console('DEBUG', "Metadata extraction for file '$file_path'");

    # Basic metadata extraction includes File Identifiers (CRS32 and ContentIdentifier), File Type and Date
    $file_metadata{'FileCRC'}           = calculate_file_crc32($file_path);
    $file_metadata{'ContentIdentifier'} = $exifTool->GetValue('ContentIdentifier', 'PrintConv') || ' ';
    $file_metadata{'FileType'}          = $exifTool->GetValue('FileTypeExtension', 'PrintConv') || ' ';

    # Date extraction with prefered tags depending on file type
    for my $entry (@prefered_date_tags){
        my ($format, $tag) = @{$entry};
        if ($format eq $file_metadata{'FileType'} || $format eq '*') {
            my $date = $exifTool->GetValue($tag, 'PrintConv');
            if (defined $date) {
                print_to_console('DEBUG', "'$tag': $date");
                if ( $date =~ /\b(\d{4}):(\d{2}):(\d{2})\b/ && $date !~ /\b0000:00:00\b/ ) {
                    $file_metadata{'Date'} = $date;
                    last;
                }
            }
            else {
                print_to_console('DEBUG', "'$tag' not found in metadata");
            }
        }
    }

    if (!defined $file_metadata{'Date'}) {
        $file_metadata{'Date'} //= '0000:01:01 00:00:00';
        print_to_console('DEBUG', "Not possible to extract valid date. Using default date for $file_path");
    }

    # Parse extracted date to compose the new file name and path
    my ($year, $month, $day, $hour, $minute, $second) = $file_metadata{'Date'} =~ /(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})/;
    $file_metadata{'year'} = $year // '0000';
    $file_metadata{'month'} = ($month =~ /^(0[1-9]|1[0-2])$/) ? $month : '01';
    $file_metadata{'day'} = $day // '01';
    $file_metadata{'hour'} = $hour  // '00';
    $file_metadata{'minute'} = $minute // '00';
    $file_metadata{'second'} = $second // '00';

    # Additional metadata for inventory only - These fields are not reelevant for the import process itself
    if($inventory_enabled) {

        $file_metadata{'ImportPath'}        = $file_path;
        $file_metadata{'FileSize'}          = $exifTool->GetValue('FileSize', 'PrintConv') || ' ';
        $file_metadata{'Make'}              = $exifTool->GetValue('Make', 'PrintConv') || ' ';
        $file_metadata{'Model'}             = $exifTool->GetValue('Model', 'PrintConv') || ' ';
        $file_metadata{'ImageSize'}         = $exifTool->GetValue('ImageSize', 'PrintConv') || ' ';
        $file_metadata{'Megapixels'}        = $exifTool->GetValue('Megapixels', 'PrintConv') || ' ';
        $file_metadata{'FocalLength'}       = $exifTool->GetValue('FocalLength', 'PrintConv') || ' ';
        $file_metadata{'ExposureTime'}      = $exifTool->GetValue('ExposureTime', 'PrintConv') || ' ';
        $file_metadata{'FNumber'}           = $exifTool->GetValue('FNumber', 'PrintConv') || ' ';
        $file_metadata{'ISO'}               = $exifTool->GetValue('ISO', 'PrintConv') || ' ';
        $file_metadata{'LensInfo'}          = $exifTool->GetValue('LensInfo', 'PrintConv') || ' ';
        $file_metadata{'Flash'}             = $exifTool->GetValue('Flash', 'PrintConv') || ' ';
        $file_metadata{'GPSInfo'}           = $exifTool->GetValue('GPSCordinates', 'PrintConv');
        # Build GPSInfo if not directly available
        $file_metadata{'GPSInfo'}          = (($exifTool->GetValue('GPSLatitude', 'PrintConv')   || ' ') . ', ' .
                                            ($exifTool->GetValue('GPSLongitude', 'PrintConv')  || ' ') . ', ' .
                                            ($exifTool->GetValue('GPSAltitude', 'PrintConv')   || ' ') . ', ' .
                                            ($exifTool->GetValue('GPSAltitudeRef', 'PrintConv')|| ' ')) unless defined $file_metadata{'GPSInfo'};
        $file_metadata{'GPSInfo'} = ' ' if($file_metadata{'GPSInfo'} eq ' ,  ,  ,  ');

        # GPS info available enables location decoding and map link generation
        if ($file_metadata{'GPSInfo'} ne ' ') {
            my ($latitude, $longitude) = convert_cordenates_to_decimal($file_metadata{'GPSInfo'});
            my %location_info = decode_location($latitude, $longitude) if((defined $latitude) && (defined $longitude));

            $file_metadata{'MapLink'} = "https://www.google.com/maps/place/$latitude,$longitude" if ((defined $latitude) && (defined $longitude));
            $file_metadata{'Location'} = $location_info{display_name} if (exists $location_info{display_name});
            $file_metadata{'Country'} = $location_info{address}{country} if (exists $location_info{address}->{country});
        } 

        $file_metadata{'MapLink'} //= ' ';
        $file_metadata{'Location'} //= ' ';
        $file_metadata{'Country'} //= ' ';


        ## DEBUG DATA
        $file_metadata{'CreateDate'} = $exifTool->GetValue('CreateDate', 'PrintConv') || ' ';
        $file_metadata{'DateTimeOriginal'} = $exifTool->GetValue('DateTimeOriginal', 'PrintConv') || ' ';
        $file_metadata{'FileModifyDate'} = $exifTool->GetValue('FileModifyDate', 'PrintConv') || ' ';
        $file_metadata{'FileCreateDate'} = $exifTool->GetValue('FileCreateDate', 'PrintConv') || ' ';
        ##
    }

    return %file_metadata;

}

# Subroutine:  add_inventory_entry
# Information: Subroutine to add a new entry to the inventory/CSV file. Each entry corresponds to a file imported into the library.
#              It is responsability of the caller to ensure that structure of the string matches the CSV header defined in @inventory_entries
# Parameters:  $_[0]: Path to the inventory/CSV file
#              $_[1]: String to be added to the inventory/CSV file
# Return:      None
sub add_inventory_entry {
    my %file_entry = @_; 
    my $import_date = strftime '%Y:%m:%d %H:%M:%S' , localtime;
    my @inventory_header = (# Import Info
                             'Imported Date', 'Imported from:', 'Destination',                 
                            # File Info
                             'File Size', 'File Type', 'Date', 'Image Size', 'File CRC32', 'Content Identifier',
                            # Camera Info
                            'Make', 'Model', 'Megapixels', 
                            # Shot Info
                            'Focal Length',  'Exposure Time', 'Aperture (f)', 'ISO', 'LensInfo', 'Flash', 
                            # Location Info
                            'GPS Info', 'Location', 'Country', 'Map Link',
                            # Debug Info
                            'CreateDate', 'DateTimeOriginal', 'FileModifyDate', 'FileCreateDate'
                            );


    my @inventory_entries = (# Import Info
                             $import_date, $file_entry{'ImportPath'}, $file_entry{'Destination'}, 
                             # File Info
                             $file_entry{'FileSize'}, $file_entry{'FileType'}, $file_entry{'Date'}, $file_entry{'ImageSize'}, $file_entry{'FileCRC'}, $file_entry{'ContentIdentifier'},
                             # Camera Info
                             $file_entry{'Make'}, $file_entry{'Model'}, $file_entry{'Megapixels'}, 
                             # Shot Info          
                             $file_entry{'FocalLength'}, $file_entry{'ExposureTime'}, $file_entry{'FNumber'}, $file_entry{'ISO'}, $file_entry{'LensInfo'}, $file_entry{'Flash'}, 
                             # Location Info
                             $file_entry{'GPSInfo'}, $file_entry{'Location'}, $file_entry{'Country'}, $file_entry{'MapLink'},
                             # Debug Info
                             $file_entry{'CreateDate'}, $file_entry{'DateTimeOriginal'}, $file_entry{'FileModifyDate'}, $file_entry{'FileCreateDate'}
                             );

    # Initialize CSV file if not exists
    if (!-e "$photo_library_path/inventory.csv") {
        print_to_console('DEBUG', "Creating inventory file at $photo_library_path/inventory.csv");
        open my $fh, '>:encoding(utf8)', File::Spec->catfile($photo_library_path, 'inventory.csv') or print_to_console('ERROR', "Could not open '$_[0]' $!");
        print $fh "sep=;\n";
        print $fh join("; ", @inventory_header) . "\n";
        close $fh;
    }

    # Add entry to CSV file
    open my $fh, '>>:encoding(utf8)', "$photo_library_path/inventory.csv" or print_to_console('ERROR', "Could not open '$_[0]' $!");
    print $fh join("; ", @inventory_entries) . "\n";
    close $fh;
}

# Subroutine:  encode_library_data_json
# Information: Subroutine to encode library data to a JSON file. 
# Parameters:  @_: Array of hashes containing all data to be stored in JSON formated file.
# Return:      None
sub encode_library_data_json {

    # Convert hash to JSON
    my $json = JSON->new->pretty->encode(\@_);
    
    # Save JSON to file
    open(my $fh, '>', 'data_to_import.json') or die "Could not open file 'output.json' $!";
    print $fh $json;
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
    
    # Process only files with supported extensions.
    if ((!defined Image::ExifTool::GetFileType($file_path)) or (!-e $file_path)) {
        print_to_console('WARNING', "Unsupported file: '$file_path'");
        $not_imported_counter++;
        return;
    }
    # Skip files with excluded extensions
    if ($file_path =~ $excluded_extensions) {
        print_to_console('WARNING', "Excluded File: '$file_path' Edit exclusions list on $config_file file");
        $not_imported_counter++;
        return;
    }

    push(@files_to_import, $file_path);
    
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

    # Extract file metadata
    my $st = stat($file_path) or print_to_console('ERROR',"Error to store file metadata:stat failed: $!");
    my %file_metadata = read_file_metadata($file_path);

    # File identifier:
    # If Apple Live Photo use ContentIdentifier as ID to ensure same name on Photo and Video file. 
    # Otherwise use FileCRC32
    my ($file_identifier) = $file_metadata{'FileCRC'};
    ($file_identifier) = $file_metadata{'ContentIdentifier'} =~ /-([A-F0-9]+)$/ if (' ' ne $file_metadata{'ContentIdentifier'});

    # Define new file path and name
    my $new_file_dir = "${photo_library_path}/$file_metadata{'year'}/$file_metadata{'month'}_${months_name[$file_metadata{'month'} - 1]}/";
    my $new_file_name = "${file_keyword}_$file_metadata{'year'}$file_metadata{'month'}$file_metadata{'day'}_$file_metadata{'hour'}$file_metadata{'minute'}$file_metadata{'second'}_$file_identifier" . lc(${file_ext});
    my $new_file_path = $new_file_dir . $new_file_name;
    $file_metadata{'Destination'} = $new_file_path;

    # Check if file already exists in library
    if (-e $new_file_path) {
        print_to_console('WARNING', "'$file_path' already in library. File Identifier ('$file_identifier') matched with file '$new_file_path'. File not imported.");
        $duplicated_counter++;
        return;
    }
    
    # my $copy_command;
    # my $remove_command;

    # if ($^O eq 'linux') {
    #      $copy_command = "cp -a '$file_path' '$new_file_path'";
    #      $remove_command = "rm '$file_path'";
    # } elsif ($^O eq 'MSWin32') {
    #     $copy_command = "robocopy \"$file_path\" \"$new_file_path\" /ZB /COPYALL";
    #     $remove_command = "del \"$file_path\"";
    # }
    # else{
    #     print_to_console('ERROR', "Unrecognized OS: $^O \n File operations not defined");
    #     return;
    # }

    if ($import_action eq 'Copy files'){      # Copy - Preserving attributes and metadata
        
        make_path($new_file_dir) unless -d $new_file_dir;
        copy($file_path, $new_file_path)? $import_counter++ : print_to_console('ERROR', "'$file_path' copy failed: $!" && return);
        utime $st->atime, $st->mtime, $new_file_path or print_to_console('ERROR', "Failed to preserve file times: $!"); # Preserve original access and modification times

        # (system($copy_command) == 0)? $import_counter++ : print_to_console('ERROR', "'$file_path' copy failed: $!" && return);
        print_to_console('VERBOSE', "[$progress_value%] File Copied :'$file_path' to '$new_file_path'");

    } elsif ($import_action eq 'Move files'){ # Move - Preserving attributes and metadata

        make_path($new_file_dir) unless -d $new_file_dir;
        move($file_path, $new_file_path)? $import_counter++ : print_to_console('ERROR', "'$file_path' move failed: $!" && return);
        utime $st->atime, $st->mtime, $new_file_path or print_to_console('ERROR', "Failed to preserve file times: $!"); # Preserve original access and modification times

        # ((system($copy_command) == 0) && (system($remove_command) == 0))? $import_counter++ : print_to_console('ERROR', "'$file_path' Move failed: $!" && return);
        print_to_console('VERBOSE', "[$progress_value%] Move File:'$file_path' to '$new_file_path'");

    } else {
        print_to_console('VERBOSE', "[$progress_value%] Dry-run:'$file_path' to '$new_file_path'");
    }
    
    # add to file inventory, if inventory enabled and not in dry-run mode
    if (($inventory_enabled) && ($import_action ne 'Dry Run')) {
        add_inventory_entry(%file_metadata);
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
    if ($process_running) {
        warning_alert("Process is already running. Wait until it finishes.");
        return;
    }

    # start process
    $process_running = 1;
    clean_console();

    # Reset counters
    $total_files = 0;
    $import_counter = 0;
    $warning_counter = 0;
    $duplicated_counter = 0;
    $error_counter = 0;
    $not_imported_counter = 0;
    $progress_value = 0;

    # Clear files to import array
    @files_to_import = ();

    # Validate Paths
    print_to_console('ERROR', "Invalid import path: $import_dir ") && show_help() unless defined $import_dir;
    print_to_console('ERROR', "Invalid Photo Library path: $photo_library_path") && show_help() unless defined $photo_library_path;
    
    # Set log file name
    if ($auto_export_log) {
        my $import_date_subfix = strftime '%Y-%m-%d_%H-%M-%S' , localtime;

        # Define log file path - different name for dry-run mode
        if (($import_action ne 'Dry Run')) {
            $log_file_path = "$photo_library_path/log/import-$import_date_subfix.log";
        }
        else {
            $log_file_path = "$photo_library_path/log/dry-run-$import_date_subfix.log";
        }

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
    print_to_console('INFO', "      - Verbose: $verbose_level | " . $verbose_options[$verbose_level]);
    print_to_console('INFO', "      - Update inventory: " . ($inventory_enabled? "Yes" : "No"));
    print_to_console('INFO', "      - Import Log: " . ($auto_export_log? "$log_file_path" : "Not generated"));
    print_to_console('INFO', "------------------------------------------------------\n");

    # Index files to import
    print_to_console('VERBOSE', "File validation for files in: $import_dir");

    find(\&index_files_to_import, $import_dir); 

    $total_files = scalar @files_to_import;
    my $processed_files = 0;

    print_to_console('INFO', "$total_files files found for import.");

    # If not in file validation mode 
    if ($import_action ne 'File validation') {

        # Import files 
        foreach my $file (@files_to_import) {
            $processed_files++;
            $progress_value = int(($processed_files / $total_files) * 100);
            update_progress_bar(($processed_files / $total_files) , 
                               "$progress_value% completed ($processed_files / $total_files) | Imported: $import_counter, Duplicated: $duplicated_counter, Warnings: $warning_counter, Errors: $error_counter");
            process_file($file);
        }
    }

    # Print import summary
    import_summary();

    # End process
    $process_running = 0;
    $progress_value = 0;
}


