# pip's declaration — the whole of what a user says, in the smallest form there is. `home.nix`
# beside it is the module this mode points at; it is empty, because the fixture exists to be a
# faithful user DIRECTORY rather than a home to evaluate (that is examples/users' job, where
# home-manager lives).
{
  contract.cli = {
    enable = true;
    configuration = ./home.nix;
  };
}
