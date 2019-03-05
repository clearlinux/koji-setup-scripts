Assumes:

* All scripts are run as the root user

How these scripts work:

#. Edit parameters.sh as needed
#. Run (playbook does only the following)
    #. deploy-koji.sh
    #. bootstrap-build.sh
#. Optionally, for supporting a full DevOps workflow, also run
    #. deploy-mash.sh
    #. deploy-git.sh
    #. deploy-upstreams.sh

If koji builder machine is not the same as koji master machine:

#. On the koji master machine, run
    #. deploy-koji-nfs-server.sh
#. On the koji builder machine, run
    #. deploy-koji-nfs-client.sh
    #. deploy-koji-builder.sh
