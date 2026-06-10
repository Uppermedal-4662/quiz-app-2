# Quiz App Development Plan (Flutter Version)

This plan outlines the phases for building the local-first, secure Quiz Android App using Flutter and Gemini API.

## Phase 1: Project Initialization & Architecture Setup ✅
- [x] Initialize Flutter project (`flutter create`).
- [x] Add dependencies (`sqflite`, `path`, `flutter_secure_storage`, `encrypt`, `google_generative_ai`, `file_picker`, `provider`, `intl`).
- [x] Define folder structure (models, services, providers, views, widgets).
- [ ] Setup basic theme and navigation.

## Phase 2: Secure Storage & Database Implementation
- [ ] Implement `SecureStorageService` for API key management.
- [x] Design and implement SQLite database schema (`DatabaseService`).
- [ ] Implement `EncryptionService` for data protection (AES).

## Phase 3: Class Management & PDF Picking
- [ ] Create UI for Class management (CRUD operations).
- [ ] Integrate `file_picker` to select PDF files.
- [ ] Implement storage logic for Class data.

## Phase 4: Gemini API Integration (PDF to JSON)
- [ ] Setup `GeminiService` using `google_generative_ai`.
- [ ] Implement PDF processing logic (extract text/bytes and send to Gemini).
- [ ] Create prompts for structured JSON extraction.
- [ ] Parse JSON and save encrypted questions to the database.

## Phase 5: Quiz Engine & Timer Implementation
- [ ] Implement Quiz logic (question selection, scoring).
- [ ] Create Timer service/controller.
- [ ] Build the Quiz execution UI (question display, options selection).

## Phase 6: UI/UX Refinement & Results Screen
- [ ] Design a polished Results screen with score summary.
- [ ] Add animations and transitions for a better user experience.
- [ ] Implement "Rich" UI elements (custom panels, progress bars).

## Phase 7: Testing & Final Polish
- [ ] Unit testing for services (Encryption, Database).
- [ ] Integration testing for the Quiz flow.
- [ ] Final UI/UX adjustments and performance optimization.
