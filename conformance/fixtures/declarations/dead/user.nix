# The gui mode is configured and never enabled — so its home and its desktop can never reach any
# host. Every line here is individually well-formed; only the pair is wrong.
{
  contract.cli.enable = true;
  contract.gui = {
    configuration = ./home.nix;
    desktop = "plasma";
  };
}
