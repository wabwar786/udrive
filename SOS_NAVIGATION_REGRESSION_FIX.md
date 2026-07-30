# SOS Navigation Regression Fix

The customer screen was appearing blank because the custom SOS navigation container had no fixed height on desktop/web layouts. The Scaffold treated it as an oversized bottom navigation area and the page body collapsed.

## Fixed
- Replaced the unconstrained custom navigation container with a fixed-height `BottomAppBar`
- Bottom navigation height is now 82 px
- Restored full Customer Home / Explore / Packages / Profile body content
- Kept the central round SOS button
- Reduced SOS button to 58 px for stable responsive layout
- Added text overflow protection for navigation labels
- Driver navigation was not changed
- WhatsApp SOS integration remains preserved
