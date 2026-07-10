# CLAUDE2.md
 
## Project: Sample 
 
### Swift conventions
- Use @Observable macro, never ObservableObject
- Prefer async/await over completion handlers for all async code
- Use Swift concurrency structured tasks — avoid unstructured Task { } unless necessary
- All network errors must be typed (no generic Error throws)
- Never force unwrap — use guard let or if let
 
### Architecture
- Feature-based folder structure: Features/FeatureName/{View, ViewModel, Model}
- Use cases live in Core/Domain/UseCases/
- Repository pattern for all data access
- DependencyContainer.shared is the composition root
 
### SwiftUI patterns
- Views are dumb — no business logic, only layout and user actions
- Use ViewModels initialized in the View's init via @State
- Prefer native SwiftUI components before reaching for custom implementations
- All lists use LazyVStack or List, never ScrollView + ForEach for large datasets
 
### Testing
- Unit tests for all ViewModels and UseCases
- Use protocol-based fakes, not mock frameworks
- UI tests only for critical user flows (onboarding, checkout, auth)
 
### What to avoid
- Singleton state outside DependencyContainer
- NotificationCenter for cross-module communication — use delegates or callbacks
- DispatchQueue.main.async — use MainActor instead