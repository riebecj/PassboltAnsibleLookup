# PassboltAnsibleLookup
Docker container pre-configured with Ansible and Passbolt for fast lookups with Kestra

Granted, the lookup subflow takes about a minute, assuming the container has been pulled before, but 
it's a much more secure method to access secrets in Kestra without having to modify the docker-compose.yml
with base64 hardcoded values.

## Prerequisites
Ensure you have all these items completed before using the container.

### Kestra Encryption Enabled
Have an [encryption key](https://kestra.io/docs/configuration-guide/encryption) configured in Kestra, 
or you won't be able to use the `SECRET` input/output type.

### Configure Kestra Secrets ENV
You will also need to add your Passbolt private key and passphrase to your ENV file and include it in your 
docker-compose.yml for Kestra. Here's Kestra's [documentation](https://kestra.io/docs/how-to-guides/secrets#using-secrets-in-kestra).

What I did was create a `.env_encoded` file in the same directory as my kestra compose YAML
with my secrets that were pre-encoded with base64:
```
SECRET_PASSBOLT_PRIVATE_KEY=AaBbCcDd1234 # My Base64 encoded private Key
SECRET_PASSBOLT_PASSPHRASE=EeFfGgHh5678 # My Base64 encoded passphrase
```

> NOTE: You need to be sure your private key is in one-line format (See [documentation](https://github.com/passbolt/lab-passbolt-ansible-collection?tab=readme-ov-file#environment-variables-for-configuration)) before you base64 encode it. 

Then added the file in the Kestra `docker-compose.yml` like so:
```yaml
kestra:
    image: kestra/kestra:latest
    env_file:
        - .env_encoded
    ... 
```

> NOTE: If you already have Kestra running, you need to `docker compose stop && docker compose up -d --build --force-recreate` to rebuild with the Env file.

## Create Flow

Once your pre-reqs are configured, you can copy/paste this flow to create it in your Kestra instance:

```yaml
id: Passbolt
namespace: passbolt  # You can change this, if you desire.
inputs:
  - id: SecretName
    type: STRING
tasks:
  - id: GetSecrets
    type: io.kestra.plugin.ansible.cli.AnsibleCLI
    outputFiles:
      - passbolt.secrets
    inputFiles:
      inventory.ini: |
        localhost ansible_connection=local
      myplaybook.yml: |
        ---
        - name: Get Passbolt Secret
          hosts: localhost
          become: yes
          become_method: sudo            
          tasks:
            - name: Set Secrets
              set_fact:
                requested_password: "{% raw %}{{ lookup('anatomicjc.passbolt.passbolt', '{% endraw %}{{ inputs.SecretName }}{% raw %}').password }}{% endraw %}"
              environment:
                PASSBOLT_BASE_URL: "https://passbolt.myendpoint.example"  # Hardcode this or use a KV store
                PASSBOLT_PRIVATE_KEY: "{{ secret('PASSBOLT_PRIVATE_KEY') }}"
                PASSBOLT_PASSPHRASE: "{{ secret('PASSBOLT_PASSPHRASE') }}"
            - name: Create File
              ansible.builtin.file:
                state: touch
                path: passbolt.secrets
                mode: '0644'
              delegate_to: localhost
            - name: Write Data
              ansible.builtin.copy:
                content: "{% raw %}{{ requested_password }}{% endraw %}"
                dest: passbolt.secrets
              delegate_to: localhost
    containerImage: ghcr.io/riebecj/passboltansiblelookup:latest  # You can also change this to a specific version.
    commands:
      - ansible-playbook -i inventory.ini myplaybook.yml
outputs:
  - id: secret
    type: SECRET
    value: "{{ read(outputs.GetSecrets.outputFiles['passbolt.secrets']) }}"
```

## Use Passbolt in Other Flows

The beauty of this is you can fetch secrets from Passbolt right when you need it. To do so, just add this step anywhere in your flow (I tend to put it just before I actually need it):

```yaml
- id: GetMySecret  # The step name. Feel free to change this.
  type: io.kestra.plugin.core.flow.Subflow
  namespace: passbolt  # if you used a different namespace than the example, change this to match.
  inputs:
      SecretName: MySecret  # Replace this with the name of your Passbolt secret.
  flowId: Passbolt  # this references the Flow ID above.
  wait: true  # This waits until the subflow finishes (useful if used in Kestra Flow logic)
```

It should pull the latest container from the packages in this repo and run the ansible CLI command to pull your secret. It will then be encrypted
by Kestra upon output. When you use it in subsequent steps, Kestra will decrypt it at runtime. To use it, you reference the `outputs`, followed by the name of the Subflow step (`GetMySecret` in the example above), followed by its `outputs`, followed by `secret`, all in a Pebble expression.

Example:
```yaml
- id: MyHTTPCall
  type: io.kestra.plugin.core.http.Request
  headers:
    Authorization: Token {{ outputs.GetMySecret.outputs.secret }} # Reference to secret
    accept: application/json
  uri: https://example.com/api/v1/path/to/my/uri
```

# Contributing
If you run into issues using the container or any process within the subflow provided above, or you have a feature request or an idea to improve the speed of execution, please submit an issue. I'm open to Pull Requests, as well.
