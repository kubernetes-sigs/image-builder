# Security

The security role enables the installation of Trivy and/or Falco to be installed directly into the image rather than
having to run privileged pods.

They can be individually enabled using the following `ansible_user_vars`. They are able to be installed in
the `node_custom_roles_pre`, `node_custom_roles_post` or just as a role reference.

```json
{
  "ansible_user_vars": "security_install_falco=true security_install_trivy=true",
  "node_custom_roles_pre": "security"
}
```