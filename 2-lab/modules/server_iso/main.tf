# Installation ISO downloaded on the server over SSH, for what libvirt cannot download itself
# (no checksum check, no gzip). Skipped if the file is already there.

resource "terraform_data" "download" {
  # A tuple, as before the module: a list of the same strings would replace the resource.
  # jsondecode returns a tuple, whatever the number of elements.
  triggers_replace = jsondecode(jsonencode(compact([var.path, var.sha256])))

  connection {
    type        = "ssh"
    host        = var.server.host
    user        = var.server.user
    private_key = file(pathexpand(var.server.private_key_path))
  }

  provisioner "remote-exec" {
    inline = concat(
      [
        "set -e",
        "if sudo test -f '${var.path}'; then echo 'ISO already there'; exit 0; fi",
        "tmp=$(mktemp -d)",
        "curl -fsSL -o \"$tmp/download\" '${var.url}'",
      ],
      var.sha256 == null ? [] : ["echo '${var.sha256}  '\"$tmp/download\" | sha256sum -c"],
      [
        var.gzip
        ? "gunzip -c \"$tmp/download\" | sudo tee '${var.path}.part' > /dev/null"
        : "sudo cp \"$tmp/download\" '${var.path}.part'",
        "rm -r \"$tmp\"",
        "sudo mv '${var.path}.part' '${var.path}'",
        "sudo sha256sum '${var.path}'",
      ],
    )
  }
}
