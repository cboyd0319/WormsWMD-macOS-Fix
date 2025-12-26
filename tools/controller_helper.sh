#!/bin/bash
#
# controller_helper.sh - Controller diagnostics and configuration helper
#
# Helps diagnose controller issues and provides configuration guidance
# for Worms W.M.D on macOS.
#
# Usage:
#   ./controller_helper.sh          # Run diagnostics
#   ./controller_helper.sh --test   # Test controller input
#

set -e


# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_help() {
    cat << 'EOF'
Worms W.M.D - Controller Helper

Diagnoses controller connectivity and provides configuration help.

USAGE:
    ./controller_helper.sh [OPTIONS]

OPTIONS:
    --test, -t      Interactive controller test
    --info, -i      Show detailed controller info
    --help, -h      Show this help

SUPPORTED CONTROLLERS:
    - Xbox Wireless Controller (via Bluetooth)
    - PlayStation DualShock 4 / DualSense (via Bluetooth or USB)
    - Nintendo Switch Pro Controller (via Bluetooth)
    - MFi (Made for iPhone) controllers
    - Generic USB/Bluetooth HID gamepads

COMMON ISSUES:
    1. Controller not detected → Try re-pairing via Bluetooth
    2. Wrong button mapping → Use Steam Big Picture mode for remapping
    3. Stick drift → Calibrate in System Preferences
    4. Input lag → Use wired connection if possible

EOF
}

# Detect connected controllers using system_profiler
detect_controllers() {
    echo -e "${BLUE}Detecting controllers...${NC}"
    echo ""

    local found=false

    # Check USB controllers
    echo -e "${CYAN}USB Controllers:${NC}"
    local usb_controllers
    usb_controllers=$(system_profiler SPUSBDataType 2>/dev/null | grep -A5 -i "controller\|gamepad\|joystick" | head -20 || true)

    if [[ -n "$usb_controllers" ]]; then
        echo "$usb_controllers" | while read -r line; do
            echo "  $line"
        done
        found=true
    else
        echo "  (none detected)"
    fi

    echo ""

    # Check Bluetooth controllers
    echo -e "${CYAN}Bluetooth Controllers:${NC}"
    local bt_controllers
    bt_controllers=$(system_profiler SPBluetoothDataType 2>/dev/null | grep -B2 -A5 -i "controller\|gamepad\|dualshock\|dualsense\|xbox\|switch pro" | head -30 || true)

    if [[ -n "$bt_controllers" ]]; then
        echo "$bt_controllers" | while read -r line; do
            echo "  $line"
        done
        found=true
    else
        echo "  (none detected)"
    fi

    echo ""

    # Check HID devices
    echo -e "${CYAN}HID Game Controllers:${NC}"
    local hid_controllers
    hid_controllers=$(ioreg -p IOUSB -l 2>/dev/null | grep -i "gamepad\|controller\|joystick" | head -10 || true)

    if [[ -z "$hid_controllers" ]]; then
        hid_controllers=$(ioreg -l 2>/dev/null | grep -i "GC.*Controller\|GameController" | head -10 || true)
    fi

    if [[ -n "$hid_controllers" ]]; then
        echo "$hid_controllers" | while read -r line; do
            local name
            name=$(echo "$line" | grep -o '".*"' | head -1 || echo "$line")
            echo "  $name"
        done
        found=true
    else
        echo "  (none detected)"
    fi

    echo ""

    if ! $found; then
        echo -e "${YELLOW}No controllers detected.${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Ensure controller is turned on"
        echo "  2. Check Bluetooth pairing in System Settings → Bluetooth"
        echo "  3. Try connecting via USB cable"
        echo "  4. Some controllers need firmware updates"
    else
        echo -e "${GREEN}Controller(s) detected!${NC}"
    fi
}

# Show detailed controller info
show_controller_info() {
    echo -e "${BLUE}Detailed Controller Information${NC}"
    echo ""

    # macOS Game Controller framework support
    echo -e "${CYAN}Game Controller Framework:${NC}"
    if [[ -d "/System/Library/Frameworks/GameController.framework" ]]; then
        echo -e "  ${GREEN}Available${NC} (macOS native controller support)"
    else
        echo -e "  ${YELLOW}Not found${NC}"
    fi

    echo ""

    # Steam controller support
    echo -e "${CYAN}Steam Controller Support:${NC}"
    if pgrep -x "steam_osx" >/dev/null 2>&1 || pgrep -x "Steam" >/dev/null 2>&1; then
        echo -e "  ${GREEN}Steam is running${NC}"
        echo "  Steam provides additional controller support via Steam Input"
        echo ""
        echo "  To configure:"
        echo "  1. Open Steam → Settings → Controller"
        echo "  2. Enable 'Enable Steam Input for Xbox/PlayStation/etc. controllers'"
        echo "  3. Optionally use Big Picture Mode for advanced remapping"
    else
        echo -e "  ${YELLOW}Steam is not running${NC}"
        echo "  Launch Steam for enhanced controller support"
    fi

    echo ""

    # Worms W.M.D controller settings location
    echo -e "${CYAN}Game Controller Settings:${NC}"
    local worms_prefs="$HOME/Library/Application Support/Team17"
    if [[ -d "$worms_prefs" ]]; then
        echo "  Settings location: $worms_prefs"
        echo ""
        echo "  Note: Worms W.M.D controller settings are configured in-game"
        echo "  Go to: Options → Controls → Controller"
    else
        echo "  Game settings not found (run game first to create)"
    fi
}

# Interactive controller test
test_controller() {
    echo -e "${BLUE}Interactive Controller Test${NC}"
    echo ""
    echo "This test uses macOS's built-in HID system to detect controller input."
    echo "Press Ctrl+C to exit."
    echo ""

    # Check if hidutil is available
    if ! command -v hidutil &>/dev/null; then
        echo -e "${YELLOW}hidutil not available for low-level testing.${NC}"
        echo ""
        echo "Alternative testing methods:"
        echo "  1. Use 'Joystick Doctor' from the App Store"
        echo "  2. Use 'Controllers Lite' from the App Store"
        echo "  3. Test in Steam Big Picture Mode → Controller Settings"
        echo "  4. Test directly in Worms W.M.D → Options → Controls"
        return
    fi

    echo "Monitoring HID events (simplified)..."
    echo "Move sticks, press buttons to see activity."
    echo ""

    # Show current HID devices
    echo "Active HID devices:"
    hidutil list 2>/dev/null | grep -i "controller\|gamepad\|joystick" | head -10 || echo "  (none matching 'controller/gamepad/joystick')"

    echo ""
    echo -e "${YELLOW}For detailed controller testing, we recommend:${NC}"
    echo "  - 'Joystick Doctor' (App Store - free)"
    echo "  - 'Gamepad Tester' (web: gamepad-tester.com)"
    echo "  - Steam Big Picture Mode controller configuration"
}

# Show configuration tips
show_tips() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Controller Configuration Tips${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}Xbox Controller:${NC}"
    echo "  - Pairs via Bluetooth (System Settings → Bluetooth)"
    echo "  - Hold Xbox button until it flashes, then pair"
    echo "  - Works natively with macOS 11+"
    echo ""
    echo -e "${CYAN}PlayStation (DualShock 4 / DualSense):${NC}"
    echo "  - Pairs via Bluetooth or USB"
    echo "  - Hold Share + PS button until light bar flashes"
    echo "  - Touchpad may not work in all games"
    echo ""
    echo -e "${CYAN}Nintendo Switch Pro Controller:${NC}"
    echo "  - Pairs via Bluetooth"
    echo "  - Hold pairing button on back until lights flash"
    echo "  - Button labels (A/B, X/Y) may be swapped"
    echo ""
    echo -e "${CYAN}Steam Controller Configuration:${NC}"
    echo "  1. Open Steam → Steam menu → Settings"
    echo "  2. Go to Controller section"
    echo "  3. Click 'General Controller Settings'"
    echo "  4. Enable support for your controller type"
    echo "  5. For game-specific: Right-click game → Properties → Controller"
    echo ""
    echo -e "${CYAN}In-Game (Worms W.M.D):${NC}"
    echo "  1. Launch the game"
    echo "  2. Go to Options → Controls"
    echo "  3. Select 'Controller' tab"
    echo "  4. Configure buttons as needed"
    echo ""
    echo -e "${CYAN}Troubleshooting:${NC}"
    echo "  - Controller not working? Try launching via Steam (not direct)"
    echo "  - Wrong buttons? Use Steam's controller remapping"
    echo "  - Input lag? Use wired connection instead of Bluetooth"
    echo "  - Drift issues? Check System Settings → Game Controllers (macOS 13+)"
}

# Parse arguments
case "${1:-}" in
    --test|-t)
        test_controller
        ;;
    --info|-i)
        show_controller_info
        ;;
    --help|-h)
        print_help
        ;;
    "")
        detect_controllers
        show_tips
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        echo "Use --help for usage"
        exit 1
        ;;
esac
