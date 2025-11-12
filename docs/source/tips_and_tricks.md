# Tips and Tricks

(workspace-to-local)=
## Working with remote ITK-SNAP workspaces

Workspaces are created in ITK-SNAP and often require some interaction. They refence files that are inside the `input` and `work` directories, so copying just the workspace file to your local laptop will not copy the images. Instead you can do the following:

```sh
# Create a temporary directory for the workspace
mkdir -p $ROOT/tmp/snapws
rm -rf $ROOT/tmp/snapws/*

# Copy the workspace and the referenced images to this location
itksnap-wt -i <path_to_workspace>/<workspace>.itksnap -a $ROOT/tmp/snapws/<workspace>.itksnap
```

You can now use Cyberduck or Filezilla to download the folder `$ROOT/tmp/snapws` and open the workspace locally. 