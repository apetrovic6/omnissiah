{
    # nixidy.target.repository = "https://github.com/apetrovic6/omnissiah.git";
    nixidy.target.repository = "https://forge.manjaca.xyz/manjo/omnissiah.git";

    # Set the target branch the rendered manifests for _this_
    # environment should be pushed to in the repository defined
    # above.
    nixidy.target.branch = "master";

    # Set the target sub-directory to copy the generated
    # manifests to when running `nixidy switch .#dev`.
    nixidy.target.rootPath = "./taghmata/manifests/dev";
}
