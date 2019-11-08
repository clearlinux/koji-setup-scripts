# Koji Setup Scripts

The purpose of these scripts it to enable setting up a koji environment quickly
with reasonable configurations.

## Assumptions

* All scripts are run as the root user
* The root user has a password set
* Basic configurations (e.g. network, time, etc.) have been applied
* Only one koji builder is required

## Unsupported Environments

* Systems that are not starting as dedicated and clean
* Systems that are not based on Clear Linux OS*

For unsupported environments, it will be up to the sysadmin to proceed at their
own discretion and fix issues that may arise on their own.

## Getting Going

1. Edit parameters.sh as needed. If running in a production environment, be
sure to supply reasonable SSL certificate field values.

1. Run the required following scripts

        deploy-koji.sh
        bootstrp-build.sh

1. Optionally, for supporting a full DevOps workflow, also run

        deploy-mash.sh
        deploy-git.sh
        deploy-upstreams.sh

If koji builder machine is not the same as koji master machine:

1. On the koji master machine, run

        deploy-koji-nfs-server.sh

1. Copy the koji builder certificate from the koji master machine to the koji
builder machine

        scp "$KOJI_PKI_DIR/$KOJI_SLAVE_FQDN.pem" "$KOJI_SLAVE_FQDN":"$KOJI_PKI_DIR"

1. On the koji builder machine, run

        deploy-koji-nfs-client.sh
        deploy-koji-builder.sh

*Other names and brands may be claimed as the property of others.
