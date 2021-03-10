# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/focal64"

  config.vm.synced_folder "dotfiles", "/home/vagrant/dotfiles"

  config.vm.provision "shell", privileged: false, inline: <<-SHELL
    dotfiles/bootstrap/foundation/linux.sh
    source /etc/profile.d/nix.sh
    source /etc/profile.d/user-shim-for-nix-path.sh
    dotfiles/bootstrap/configuration.sh
  SHELL
end
