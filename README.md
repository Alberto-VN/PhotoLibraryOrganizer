# Photo Organizer
Script to organize your photo library. CLI and GUI modes for Windows and Linux

# Usage

```
PhotoLibraryOrganizer.exe <import_dir> <photo_library_path> [-k <file_keyword>] [-v] [-mv] [i] [-gui]

Options:
  <import_dir>          : (Mandatory if CLI) Path of files to import.
  <photo_library_path>  : (Mandatory if CLI) Path of your photo library.
  -k <file_keyword>     : (Optional. Default: IMG) Keyword to be added at the begining of file name.
  -gui                  : Run the GUI version of the program
  -cp                   : Copy files to library. Default option. 
  -mv                   : Move files to library. If not selected files are copied. 
  -dry-run              : Dry-Run to evaluate if files are in library. Files are not moved, copied, or added to inventory
  -i                    : Update Photo Inventory Generates a CSV file with an inventory of all imported assests. 
  -v                    : Verbose mode. 
  -h                    : Show this help message

```

# Setting up the environment

Requires Perl v5.40.x and dependencies listed in cpanfile.

Install dependencies by running:

```
    cpan install App::cpanminus
    cpanm --installdeps .
```


# Windows 

- Install all dependencies
- Execute "build_exe.cmd" in order to generate an .exe file.

# Linux 

Tested on Ubuntu

- Set permisions to execute 'run-photo-organizer.sh'
   'chmod +x ./run-photo-organizer.sh'

- run script with any of the following parameters:

   - 'test'    -> Install dependencies and run the script for testing"
   - 'run'     -> Run the script - (Dependencies must be installed first)"
   - 'install' -> Install the desktop entry
   - 'remove'  -> Remove the desktop entry

  E.g.

   './run-photo-organizer.sh install'
