pp --gui -o PhotoLibraryOrganizer.exe photo-library-organizer.pl
perl -e "use Win32::Exe; $exe = Win32::Exe->new('PhotoLibraryOrganizer.exe'); $exe->set_single_group_icon('./icons/PhotoLibraryOrganizer_32x32.ico'); $exe->write;"
pause