# Ansible Windows Development Environment

> **Note**: This is an internal development environment template intended specifically for our team's use. It is not designed or maintained for general public use and may contain organization-specific configurations.

This repository provides a containerized development environment for working with Ansible, specifically focused on Debian 13 automation. It uses VS Code Dev Containers with Podman for container management and includes Molecule for testing roles.

## Project Structure

```
.
├── ansible.cfg             # Ansible configuration file
├── requirements.txt        # Python dependencies
├── setup-dev-env.ps1      # PowerShell setup script
└── roles/                 # Directory containing Ansible roles
    └── myrole/           # Example role structure
        ├── meta/         # Role metadata
        ├── molecule/     # Molecule test configurations
        ├── tasks/       # Role tasks
        └── templates/   # Jinja2 templates
```

## Development Environment

The development environment is configured using VS Code Dev Containers and includes:

- Podman for container management
- Python with Ansible
- Molecule for role testing
- VS Code extensions for Ansible, Python, and container management

### Prerequisites

- VS Code with Dev Containers extension
- Podman installed on the host system

### Getting Started

1. Clone this repository
2. Run the setup-dev-env.ps1 script as Administrator to setup the pre-requisites
   > Note: The setup script is idempotent and can be safely re-run at any time to ensure your environment is properly configured.
3. Open in VS Code
4. When prompted, click "Reopen in Container"
5. VS Code will build and start the development container

## Working with Roles

Each role should:
- Include Molecule tests
- Follow Ansible best practices
- Include proper documentation
- Be tested against Windows targets

### Testing Roles

To test a role using Molecule:

```bash
cd roles/your_role
molecule test
```

## Configuration

### ansible.cfg

The project includes a custom `ansible.cfg` that sets:
- Role path configuration
- Disabled host key checking
- Custom temporary file locations

### Dev Container

The Dev Container configuration:
- Mounts the Podman socket
- Installs required VS Code extensions
- Sets up Python dependencies

## Contributing

1. Create a new branch for your changes
2. Install pre-commit hooks:
   ```bash
   pre-commit install
   ```
3. Include Molecule tests for any new roles
4. Ensure all tests pass
5. Submit a pull request

### Pre-commit Hooks

This project uses pre-commit hooks to ensure code quality. The following checks are run automatically before each commit:
- YAML syntax checking
- Trailing whitespace removal
- YAML/JSON formatting
- Ansible-lint
- Python code formatting (black)

To manually run all pre-commit hooks:
```bash
pre-commit run --all-files
```

## License

MIT License

Copyright (c) 2025 bazauto

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
