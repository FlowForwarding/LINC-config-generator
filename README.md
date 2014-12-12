# LINC Configuration generator


Utility that takes a JSON topology description file and generates a
`sys.config` configuration file for the
[LINC Switch](http://github.com/FlowForwarding/LINC-Switch).

## Usage

Compile and test:

```shell
$ make compile test
```

Run the config generator:

```shell
$ make run controller_port=6653 controller_ip=127.0.0.1 topology=topology.json config_template=config
```

This will generate a `sys.config` file in $PWD.

Defaults values are:

* controller_port: `6653`,
* controller_ip: `localhost`,
* topology_template: `$PWD/json_example.json`,
* config_template: `$PWD/sys.config.template`.
