${jsonencode({
  root_enc_password = "!"
  users = [{
    username = "sherpa"
    enc_password = password_hash
    groups = []
    sudo = true
  }]
})}
