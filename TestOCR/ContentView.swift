//
//  ContentView.swift
//  TestOCR
//
//  Created by Brian Anashari on 11/08/26.
//

import PhotosUI
import SwiftUI
import UIKit
import Vision

struct ContentView: View {
    @AppStorage("ocr_api_base_url") private var apiBaseURL = "http://10.202.223.137:8000"
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isShowingCamera = false
    @State private var recognizedText = ""
    @State private var apiResponseText = ""
    @State private var isProcessingOCR = false
    @State private var isSendingRequest = false
    @State private var errorMessage: String?
    @State private var sourceSelection: ImageSource?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sourceButtons
                    apiConfigurationSection
                    previewSection
                    recognizedTextSection
                    sendSection
                    responseSection
                }
                .padding()
            }
            .navigationTitle("OCR Product POC")
            .confirmationDialog("Pilih sumber foto", isPresented: sourceSelectionBinding) {
                Button("Kamera") {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        isShowingCamera = true
                    } else {
                        errorMessage = "Kamera tidak tersedia di device ini. Coba pilih dari galeri."
                    }
                }
                Button("Galeri") {
                    sourceSelection = .photoLibrary
                }
                Button("Batal", role: .cancel) {
                    sourceSelection = nil
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraImagePicker(image: $selectedImage)
            }
            .photosPicker(isPresented: isPhotoPickerPresentedBinding, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) {
                Task {
                    await loadSelectedPhoto()
                }
            }
            .onChange(of: selectedImage) {
                recognizedText = ""
                apiResponseText = ""
                errorMessage = nil
            }
            .alert("Terjadi kesalahan", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var sourceButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Flow")
                .font(.headline)

            Text("Foto produk -> OCR -> text -> kirim ke endpoint /api/identity/resolve-from-ocr")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                sourceSelection = .chooser
            } label: {
                Label("Pilih Foto Produk", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if selectedImage != nil {
                Button {
                    Task {
                        await runOCR()
                    }
                } label: {
                    HStack {
                        if isProcessingOCR {
                            ProgressView()
                        }
                        Text(isProcessingOCR ? "Memproses OCR..." : "Run OCR")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isProcessingOCR || isSendingRequest)
            }
        }
    }

    private var apiConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Base URL")
                .font(.headline)

            TextField("http://192.168.1.10:8000", text: $apiBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(12)
                .background(.thinMaterial)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.quaternary, lineWidth: 1)
                )

            Text("Simulator bisa pakai 127.0.0.1. Kalau pakai real device, ganti ke IP laptop/server kamu di jaringan yang sama, misalnya http://192.168.1.10:8000")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview Foto")
                .font(.headline)

            Group {
                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 16))
                } else {
                    ContentUnavailableView(
                        "Belum ada foto",
                        systemImage: "photo",
                        description: Text("Ambil foto produk atau pilih dari galeri untuk mulai OCR.")
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var recognizedTextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hasil OCR")
                .font(.headline)

            TextEditor(text: $recognizedText)
                .frame(minHeight: 160)
                .padding(8)
                .background(.thinMaterial)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.quaternary, lineWidth: 1)
                )

            Text("Text bisa diedit dulu sebelum dikirim ke API.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send to API")
                .font(.headline)

            Button {
                Task {
                    await sendOCRTextToAPI()
                }
            } label: {
                HStack {
                    if isSendingRequest {
                        ProgressView()
                    }
                    Text(isSendingRequest ? "Mengirim ke API..." : "Send OCR Text to Endpoint")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessingOCR || isSendingRequest)
        }
    }

    private var responseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Response API")
                .font(.headline)

            ScrollView {
                Text(apiResponseText.isEmpty ? "Belum ada response." : apiResponseText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 200)
            .padding(12)
            .background(.thinMaterial)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.quaternary, lineWidth: 1)
            )
        }
    }

    private var sourceSelectionBinding: Binding<Bool> {
        Binding(
            get: { sourceSelection == .chooser },
            set: { newValue in
                if !newValue {
                    sourceSelection = nil
                }
            }
        )
    }

    private var isPhotoPickerPresentedBinding: Binding<Bool> {
        Binding(
            get: { sourceSelection == .photoLibrary },
            set: { newValue in
                if !newValue {
                    sourceSelection = nil
                }
            }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }

    @MainActor
    private func loadSelectedPhoto() async {
        guard let selectedPhotoItem else {
            return
        }

        do {
            if let data = try await selectedPhotoItem.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                selectedImage = image
                sourceSelection = nil
            } else {
                errorMessage = "Gagal membaca foto yang dipilih."
            }
        } catch {
            errorMessage = "Gagal load foto: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func runOCR() async {
        guard let selectedImage else {
            errorMessage = "Pilih foto dulu sebelum menjalankan OCR."
            return
        }

        isProcessingOCR = true
        errorMessage = nil

        defer {
            isProcessingOCR = false
        }

        do {
            recognizedText = try await OCRService.recognizeText(from: selectedImage)
            print("[OCR SUCCESS] recognizedText=\(recognizedText)")
            if recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "OCR selesai, tapi tidak ada teks yang terbaca."
            }
        } catch {
            errorMessage = "OCR gagal: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func sendOCRTextToAPI() async {
        let text = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            errorMessage = "Text OCR kosong. Jalankan OCR atau edit text dulu."
            return
        }

        isSendingRequest = true
        errorMessage = nil

        defer {
            isSendingRequest = false
        }

        do {
            let response = try await OCRIdentityAPI.resolve(baseURLString: baseURL, text: text)
            apiResponseText = response.prettyPrintedJSON
            print("[API RESPONSE] \(response.prettyPrintedJSON)")
        } catch let error as URLError where error.code == .cannotConnectToHost {
            errorMessage = APIRequestError.cannotConnectToServer(baseURL: baseURL).localizedDescription
        } catch let error as URLError where error.code == .notConnectedToInternet {
            errorMessage = APIRequestError.localNetworkAccessDenied(baseURL: baseURL).localizedDescription
        } catch let error as URLError where error.code == .timedOut {
            errorMessage = "Request timeout ke \(baseURL). Pastikan API hidup dan device bisa menjangkau server."
        } catch {
            errorMessage = "Request API gagal: \(error.localizedDescription)"
        }
    }
}

private enum ImageSource {
    case chooser
    case photoLibrary
}

private enum OCRService {
    static func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRProcessingError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage)

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private enum OCRProcessingError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Format gambar tidak didukung untuk OCR."
        }
    }
}

private enum OCRIdentityAPI {
    private static let apiKey = "0262afa041d297eb77f479ff93aae46397581c6a879df60bf69b2b7dfd30dad3"

    static func resolve(baseURLString: String, text: String) async throws -> APIResponseEnvelope {
        let endpoint = try endpointURL(from: baseURLString)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONEncoder().encode(ResolveFromOCRRequest(text: text, useQueryBuckets: false, useRawWebSearchOnly: false, useBucketedWebSearch: true))

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIRequestError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw APIRequestError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        return APIResponseEnvelope(statusCode: httpResponse.statusCode, data: data)
    }

    private static func endpointURL(from baseURLString: String) throws -> URL {
        guard !baseURLString.isEmpty,
              var components = URLComponents(string: baseURLString) else {
            throw APIRequestError.invalidBaseURL
        }

        let cleanedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = "api/identity/resolve-from-ocr"
        components.path = cleanedPath.isEmpty ? "/\(endpointPath)" : "/\(cleanedPath)/\(endpointPath)"

        guard let url = components.url else {
            throw APIRequestError.invalidBaseURL
        }

        return url
    }
}

private struct ResolveFromOCRRequest: Encodable {
    let text: String
    let useQueryBuckets: Bool?
    let useRawWebSearchOnly: Bool?
    let useBucketedWebSearch: Bool?

    enum CodingKeys: String, CodingKey {
        case text
        case useQueryBuckets = "use_query_buckets"
        case useRawWebSearchOnly = "use_raw_web_search_only"
        case useBucketedWebSearch = "use_bucketed_web_search"
    }
}

private struct APIResponseEnvelope {
    let statusCode: Int
    let data: Data

    var prettyPrintedJSON: String {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: prettyData, encoding: .utf8) {
            return "HTTP \(statusCode)\n\n\(string)"
        }

        let fallback = String(data: data, encoding: .utf8) ?? "Unable to decode response body"
        return "HTTP \(statusCode)\n\n\(fallback)"
    }
}

private enum APIRequestError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case serverError(statusCode: Int, message: String)
    case cannotConnectToServer(baseURL: String)
    case localNetworkAccessDenied(baseURL: String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Base URL API tidak valid. Contoh: http://192.168.1.10:8000"
        case .invalidResponse:
            return "Response API tidak valid."
        case let .serverError(statusCode, message):
            return "Server error \(statusCode): \(message)"
        case let .cannotConnectToServer(baseURL):
            if baseURL.contains("127.0.0.1") || baseURL.contains("localhost") {
                return "Tidak bisa connect ke \(baseURL). Kalau app jalan di real device, 127.0.0.1/localhost menunjuk ke iPhone itu sendiri, bukan ke laptop/server. Ganti ke IP laptop/server di jaringan yang sama, misalnya http://192.168.1.10:8000"
            }

            return "Tidak bisa connect ke server di \(baseURL). Pastikan API hidup, device dan server ada di jaringan Wi-Fi yang sama, dan port 8000 bisa diakses."
        case let .localNetworkAccessDenied(baseURL):
            return "Akses local network ke \(baseURL) ditolak iPhone. Buka Settings > Privacy & Security > Local Network, lalu aktifkan izin untuk app ini. Setelah itu tutup app dan buka lagi."
        }
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(image: $image, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        @Binding private var image: UIImage?
        private let dismiss: DismissAction

        init(image: Binding<UIImage?>, dismiss: DismissAction) {
            _image = image
            self.dismiss = dismiss
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            image = info[.originalImage] as? UIImage
            dismiss()
        }
    }
}

#Preview {
    ContentView()
}
