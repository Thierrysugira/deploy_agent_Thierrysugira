#!/bin/bash

# ---------- Pre-flight checks ----------
if ! command -v python3 > /dev/null 2>&1; then
    echo "Error: python3 is not installed."
    exit 1
fi

if ! command -v zip > /dev/null 2>&1; then
    echo "Error: zip is not installed."
    exit 1
fi

echo "All pre-flight checks passed."

# ---------- Project name and folders ----------
read -p "Enter project name: " project_name

if [ -z "$project_name" ]; then
    echo "Error: name cannot be empty."
    exit 1
fi

project_dir="attendance_tracker_$project_name"

if [ -d "$project_dir" ]; then
    read -p "Directory exists. Overwrite? (y/n): " answer
    if [ "$answer" = "y" ]; then
        rm -rf "$project_dir"
    else
        echo "Aborting."
        exit 1
    fi
fi

mkdir -p "$project_dir/Helpers"
mkdir -p "$project_dir/reports"
echo "Project structure created."

# ---------- Copy template files ----------
cp templates/attendance_checker.py "$project_dir/"
cp templates/config.json "$project_dir/Helpers/"
echo "Files copied."

# ---------- Roster (Option A) ----------
read -p "How many students to copy? " count
head -n $((count + 1)) templates/assets.csv > "$project_dir/Helpers/assets.csv"
sed -i "s/\"total_sessions\": [0-9]*/\"total_sessions\": 5/" "$project_dir/Helpers/config.json"
echo "Roster created with $count students."

# ---------- Permissions ----------
chmod +x "$project_dir/attendance_checker.py"
chmod 600 "$project_dir/Helpers/config.json"
echo "Permissions set:"
ls -l "$project_dir/attendance_checker.py" "$project_dir/Helpers/config.json"
