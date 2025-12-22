#!/bin/bash


# Set the Perl library path
export PERL5LIB="$HOME/perl5/lib/perl5:${PERL5LIB:+:$PERL5LIB}" 

# Get the directory where the script is executed
SCRIPT_DIR="$(pwd)"

# Target location for the .desktop file
DESKTOP_FILE="$HOME/.local/share/applications/photo-library-organizer.desktop"
SELECTION="$1"

if [ "$SELECTION" == "" ]; then
    echo ""
    echo "------------------------------"
    echo "  Photo Library Organizer     "
    echo "------------------------------"
    echo "Select an action: "
    echo "   'test'    -> Install dependencies and run the script for testing"
    echo "   'run'     -> Run the script - (Dependencies must be installed first)"
    echo "   'install' -> Install the desktop entry (Ubuntu)"
    echo "   'remove'  -> Remove the desktop entry (Ubuntu)"
    echo "------------------------------"
    echo ""
    read -p "Enter your choice: " SELECTION
    echo ""
fi

# Check argument
case "$SELECTION" in

  test)
  
    # Install dependencies
    echo ""
    echo "-------------------------------"
    echo "Installing Perl dependencies..."
    echo "-------------------------------"
    cpan install App::cpanminus
    cpanm --installdeps .
    
    # Run Photo Organizer
    echo ""
    echo "-------------------------------"      
    echo "Run Photo Organizer"
    echo "-------------------------------"      
    perl "./src/photo-library-organizer.pl"
    ;;

  run)
    # Run Photo Organizer
    perl "./src/photo-library-organizer.pl"
    ;;

  install)

    # Install dependencies
    echo ""
    echo "-------------------------------"
    echo "Installing Perl dependencies..."
    echo "-------------------------------"
    echo "Installing Perl dependencies..."
    echo "Installing Perl dependencies..."
    cpan install App::cpanminus
    cpanm --installdeps .
    echo ""
    echo "-------------------------------"
    echo " - Dependencies installed. See log for details."
    # Create the .desktop file
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Name=Photo Organizer
Comment=Photo Management Software
Exec=$SCRIPT_DIR/run-photo-organizer.sh run
Path=$SCRIPT_DIR/
Icon=$SCRIPT_DIR/icons/PhotoLibraryOrganizer.png
Terminal=false
Type=Application
Categories=Utility;Development;
EOF
    chmod +x "$DESKTOP_FILE"
    update-desktop-database ~/.local/share/applications
    echo " - Desktop entry created: $DESKTOP_FILE"
    echo " - Run Photo Organizer"
    echo "-------------------------------"      
    perl "./src/photo-library-organizer.pl"

    ;;

  remove)
    if [ -f "$DESKTOP_FILE" ]; then
      rm "$DESKTOP_FILE"
      echo "Desktop entry removed: $DESKTOP_FILE"
    else
      echo "No desktop entry found at: $DESKTOP_FILE"
    fi
    update-desktop-database ~/.local/share/applications
    ;;

  *)
    echo "$SELECTION is invalid. Please select 'test', 'run', 'install', or 'remove'."
    exit 1
    ;;
esac
    