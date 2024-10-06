FROM cytopia/ansible:latest-tools

RUN ansible-galaxy collection install anatomicjc.passbolt
RUN python -m pip install py-passbolt
