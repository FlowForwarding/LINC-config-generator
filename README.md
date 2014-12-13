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

## Topology file ##

Topology file should have two keys: `switchConfig` and `linkConfig`. Values
of both should be arrays of objects representing respectively switches
and links between them. A switch object is required to have a `nodeDpid`
key which value is a switch datapath id. A link object describe how
the switches are connected and is expected to have `nodeDpid1` and
`nodeDpid2` that represent datapath ids of the switches defined in the
`switchConfig`. The link object also have to include `params` key
whose value is an object with ports. The ports are defined as follows:
```
"port1": 20
"port2": 21
```

The value is the port number of the corresponding `nodeDpid1` (i.e.
first port is assumed to be attached to switch with `nodeDpid1` and so on).
The last key of the link object is a `type`. It can has two values:
either "pktOptLink" or "wdmLink". The first is for links between
packet and optical ports and the other one is for optical links.

Example topology file:
```JSON
{
    "switchConfig": [
        {
            "nodeDpid": "00:00:ff:ff:ff:ff:ff:02",
        },
        {
            "nodeDpid": "00:00:ff:ff:ff:ff:ff:03",
        }
    ],

    "linkConfig": [
        {
            "nodeDpid1": "00:00:ff:ff:ff:ff:ff:01",
            "nodeDpid2": "00:00:ff:ff:ff:ff:ff:02",
            "params": {
                "port1": 101,
                "port2": 201
            },
            "type": "pktOptLink"
        },
        {
            "nodeDpid1": "00:00:ff:ff:ff:ff:ff:02",
            "nodeDpid2": "00:00:ff:ff:ff:ff:ff:03",
            "params": {
                "port1": 202,
                "port2": 301
            },
            "type": "wdmLink"
        },
        {
            "nodeDpid1": "00:00:ff:ff:ff:ff:ff:03",
            "nodeDpid2": "00:00:ff:ff:ff:ff:ff:04",
            "params": {
                "port1": 302,
                "port2": 401
            },
            "type": "pktOptLink"
        }
    ]
}
```
