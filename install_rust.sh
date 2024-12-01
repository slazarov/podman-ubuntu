#!/bin/bash

#curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

wget https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init
chmod +x rustup-init

./rustup-init
