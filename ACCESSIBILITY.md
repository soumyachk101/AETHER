# Accessibility Statement for AETHER

AETHER is committed to ensuring digital accessibility for people of all abilities. We are continually improving the user experience for everyone and applying the relevant accessibility standards.

---

## Conformance Status

The Web Content Accessibility Guidelines (WCAG) defines requirements for designers and developers to improve accessibility for people with disabilities. It defines three levels of conformance: Level A, Level AA, and Level AAA.

AETHER strives to conform to **WCAG 2.1 Level AA** standards across its web interface (`AETHER-web`) and desktop shells (`AETHER-swift` and `AETHER-rust`).

---

## Accessibility Features

Key accessibility considerations in AETHER include:

- **Keyboard Navigation**: Interactive elements across the sidebar, document editor, and chat input are reachable and operable via keyboard commands.
- **Color Contrast**: Dark and light themes are tailored to meet or exceed minimum contrast ratio requirements for readability.
- **Screen Reader Support**: Semantic HTML elements and ARIA roles/labels are used where custom components are implemented.
- **Reduced Motion**: Respects system preferences for reduced motion across animated transitions and canvas visualizers.
- **Resizable Text**: Supports browser and OS level zooming without breaking layout readability.

---

## Known Limitations

While we strive for comprehensive accessibility, some areas are still actively being improved:
- Complex canvas elements in visual node maps may require screen reader text alternatives.
- Advanced syntax highlighting inside code editors may vary in contrast depending on custom user themes.

---

## Feedback and Reporting

We welcome your feedback on the accessibility of AETHER. Please let us know if you encounter accessibility barriers:

- **Maintainer**: Soumya Chakraborty
- **Email**: `soumya.chk101@gmail.com`
- **GitHub Issues**: [Open an Accessibility Issue](https://github.com/soumyachk101/AETHER/issues)

We try to respond to feedback within 3 business days.
