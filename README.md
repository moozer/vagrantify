Vagrantify
===========

In order to make a standardized vagrant box, certain tweaks 
like ssh keys and password mus be handled.

The playbook handles that.

Currently, it is tested on openbsd 5.7

Usage:
------

1. Create your local invetory file
   cp inventory.orig inventory

2. edit inventory
   change name, ip and whatever else is needed

3. Apply the playbook
   ansible-playbook --ask-pass -i inventory playbook.yml

4. create vagrant box

Go here for details on how to create a vagrant box. 
- https://moozing.wordpress.com/2015/07/29/pushing-libvirt-vagrant-boxes-to-hashicorp/


Issues:
-------

* "sed -i ..." is not supported by 5.7, but will be in 5.8
  This is relevant for the automatic replace of insecure keys.
  Since vagrant and root passwords and key should be changed
  anyway, we will leave it for now.

  Added *config.ssh.insert_key = false* to Vagrantfile


