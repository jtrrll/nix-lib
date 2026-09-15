{
  config.perSystem = _: {
    config.files.file = {
      ".github/ISSUE_TEMPLATE/config.yaml".text = ''
        ---
        blank_issues_enabled: false
        ...
      '';

      ".github/ISSUE_TEMPLATE/bug_report.yaml".text = ''
        ---
        name: 🐛 Bug Report
        description: Report a bug that should be fixed
        labels: [bug]
        body:
          - type: markdown
            attributes:
              value: |
                Thank you for submitting a bug report! It helps make this library better.

                Make sure you are using the latest version of this library.
                The bug you are experiencing may already have been fixed.

                Please try to include as much information as possible!

          - type: input
            attributes:
              label: What version are you using?
          - type: textarea
            attributes:
              label: What is the expected behavior?
              description: Please provide text instead of a screenshot.
            validations:
              required: true
          - type: textarea
            attributes:
              label: What is the actual behavior?
              description: Please provide text instead of a screenshot.
            validations:
              required: true
          - type: textarea
            attributes:
              label: What steps will reproduce the bug?
              description: Explain the steps and provide a code snippet that can reproduce it.
            validations:
              required: true
          - type: textarea
            attributes:
              label: Additional information
              description: Is there anything else you think we should know?
        ...
      '';

      ".github/ISSUE_TEMPLATE/feature_request.yaml".text = ''
        ---
        name: 🚀 Feature Request
        description: Suggest a feature, idea, or enhancement
        labels: [feature]
        body:
          - type: markdown
            attributes:
              value: |
                Thank you for submitting a feature request! It helps make this library better.

          - type: textarea
            attributes:
              label: What problem would this feature solve?
            validations:
              required: true
          - type: textarea
            attributes:
              label: What solution are you proposing?
            validations:
              required: true
          - type: textarea
            attributes:
              label: What alternatives have you considered?
        ...
      '';

      ".github/ISSUE_TEMPLATE/documentation_issue.yaml".text = ''
        ---
        name: 📗 Documentation Issue
        description: Report missing or incorrect documentation
        labels: [documentation]
        body:
          - type: markdown
            attributes:
              value: |
                Thank you for submitting a documentation issue! It helps make this library better.

          - type: dropdown
            attributes:
              label: What is the type of issue?
              multiple: true
              options:
                - Documentation is missing
                - Documentation is incorrect
                - Documentation is confusing
                - Example code is not working
                - Something else
          - type: textarea
            attributes:
              label: What is the issue?
            validations:
              required: true
          - type: textarea
            attributes:
              label: Where did you find it?
              description: If possible, please provide the URL(s) where you found this issue.
            validations:
              required: true
        ...
      '';
    };
  };
}
