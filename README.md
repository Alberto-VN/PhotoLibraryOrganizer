# PhotoLibraryOrganizer
Script to organize your photo library. CLI and GUI modes.

# Usage

```
PhotoLibraryOrganizer.exe <import_dir> <photo_library_path> [-k <file_keyword>] [-v] [-mv] [i] [-gui]

Options:
  <import_dir>          : (Mandatory if CLI) Path of files to import.
  <photo_library_path>  : (Mandatory if CLI) Path of your photo library.
  -k <file_keyword>     : (Optional. Default: IMG) Keyword to be added at the begining of file name.
  -gui                  : Run the GUI version of the program
  -mv                   : Move files to library. If not selected files are copied. 
  -i                    : Update Photo Inventory Generates a CSV file with an inventory of all imported assests. 
  -v                    : Verbose mode. 
  -h                    : Show this help message

```

# Setting up the environment

Strawberry Perl v5.40.0.1 (2024-08-10)

Required additional modules that need to be installed using cpanm:
- Image::ExifTool 
- Digest::CRC
- Config::Tiny
- TK (Version used: https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/patched_cpan_modules/Tk-804.036_001.tar.gz) 