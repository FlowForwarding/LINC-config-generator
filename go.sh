#!/bin/bash
make && ./config_generator $PWD/json_example.json $PWD/sys.config.template localhost 4343 && cat sys.config