#!/usr/bin/env bash

rm -rf .openzeppelin/unknown-1337.json
rm -rf build/contracts/*
cp -rvf build/keep/* build/contracts/
truffle compile --all