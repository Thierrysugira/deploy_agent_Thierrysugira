if ! command -v ??? > /dev/null 2>&1; then
    echo "Error: ??? is not installed."
    exit 1
fi#!/bin/bash

if ! command -v python3 > /dev/null 2>&1; then
    echo "Error: python3 is not installed."
    exit 1
fi

echo "python3 found."
