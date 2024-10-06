FROM cytopia/ansible:latest-tools

RUN ansible-galaxy collection install anatomicjc.passbolt && \
    python -m pip install --no-cache-dir py-passbolt==0.0.18
