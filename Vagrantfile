# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/focal64"

  config.vm.synced_folder "dotfiles", "/home/vagrant/dotfiles"

  # enable swapping to prevent building being killed by OOM - https://superuser.com/a/1124078
  config.vm.provision "shell", inline: <<-SHELL
    apt update && apt install swapspace -y
  SHELL

  config.vm.provision "shell", privileged: false, inline: <<-SHELL
    dotfiles/bootstrap/foundation/linux.sh
    source /etc/profile.d/nix.sh
    source /etc/profile.d/user-shim-for-nix-path.sh
    dotfiles/bootstrap/configuration.sh
  SHELL
end
