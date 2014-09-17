# LINC Configuration generator


Utility that takes a JSON topology description file and generates a `sys.config` configuration file for the [LINC Switch](http://github.com/FlowForwarding/LINC-Switch).

## Usage

Compile:

```
$ make
```

run the config generator:

```
$ ./config_generator $PWD/json_example.json $PWD/sys.config.template localhost 4343
```

This will generate a `sys.config` file in $PWD.
