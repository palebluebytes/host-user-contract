# The control: byte-identical settings, plus the one line `dead/` is missing.
{
  contract.cli.enable = true;
  contract.gui = {
    enable = true;
    configuration = ./home.nix;
    desktop = "plasma";
  };
}
