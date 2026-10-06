import SwiftUI
import QuickTileCore

struct AgentRequestView: View {
    @EnvironmentObject private var model: PhoneModel
    @State private var answers: [String:String] = [:]
    @State private var selectedID: UUID?
    @State private var customQuestions = Set<String>()
    @FocusState private var focusedQuestion: String?
    private var request: AgentInputRequest? { model.agentRequests.first { $0.id == selectedID } ?? model.agentRequests.first }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    if model.agentRequestLoading && model.agentRequests.isEmpty {
                        ProgressView().frame(maxWidth:.infinity).padding(.top,40)
                    } else if let request {
                        if model.agentRequests.count > 1 {
                            Picker("Request",selection:Binding(get:{request.id},set:{selectedID = $0; answers = [:]})) {
                                ForEach(model.agentRequests) { Text($0.title).tag($0.id) }
                            }.pickerStyle(.menu)
                        }
                        if request.kind == .permission {
                            Text(request.title).font(.title3.weight(.semibold))
                            if let detail = request.detail {
                                Text(detail).font(.footnote.monospaced()).textSelection(.enabled)
                                    .padding(14).frame(maxWidth:.infinity,alignment:.leading)
                                    .background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:14))
                            }
                            if request.canReply {
                                HStack(spacing:12) {
                                    Button("Decline") { model.replyToAgent(request,decision:.deny) }.buttonStyle(.bordered)
                                    Button("Allow once") { model.replyToAgent(request,decision:.approveOnce) }.buttonStyle(.borderedProminent)
                                }.disabled(model.agentReplyBusy)
                            }
                        } else {
                            ForEach(request.questions) { question in
                                VStack(alignment:.leading,spacing:12) {
                                    Text(question.text).font(.title3.weight(.semibold))
                                    ForEach(Array(question.options.enumerated()),id:\.offset) { _, option in
                                        Button {
                                            answers[question.id] = option.label; customQuestions.remove(question.id); focusedQuestion = nil; model.feedback(.selection)
                                        } label: {
                                            HStack(spacing:12) {
                                                VStack(alignment:.leading,spacing:4) {
                                                    Text(option.label).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                                    if !option.detail.isEmpty { Text(option.detail).font(.footnote).foregroundStyle(.secondary) }
                                                }
                                                Spacer(minLength:0)
                                                Image(systemName:answers[question.id] == option.label ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(answers[question.id] == option.label ? Color.accentColor : Color.secondary)
                                            }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
                                                .background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:14))
                                        }.buttonStyle(.plain).disabled(!request.canReply || model.agentReplyBusy)
                                    }
                                    if question.allowsText && request.canReply {
                                        if !question.options.isEmpty && !customQuestions.contains(question.id) {
                                            Button("Write an answer") { answers[question.id] = ""; customQuestions.insert(question.id); focusedQuestion = question.id }
                                                .font(.subheadline).disabled(model.agentReplyBusy)
                                        } else if question.secret {
                                            SecureField("Your answer",text:answer(question.id)).textContentType(.none).focused($focusedQuestion, equals: question.id)
                                                .padding(14).background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:14))
                                        } else {
                                            TextField(question.options.isEmpty ? "Your answer" : "Or type an answer",text:answer(question.id),axis:.vertical)
                                                .focused($focusedQuestion, equals: question.id)
                                                .lineLimit(2...6).padding(14)
                                                .background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:14))
                                        }
                                    }
                                }
                            }
                            if request.canReply {
                                Button { model.replyToAgent(request,answers:answers) } label: {
                                    HStack { if model.agentReplyBusy { ProgressView().tint(.white) }; Text("Send answer") }.frame(maxWidth:.infinity).padding(.vertical,6)
                                }.buttonStyle(.borderedProminent)
                                    .disabled(model.agentReplyBusy || !request.questions.allSatisfy { !(answers[$0.id] ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty })
                            }
                        }
                        if !request.canReply {
                            Text("Answer this request in Codex on your Mac. It isn’t available through QuickTile’s reply connection.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else if model.agentRequestError == nil {
                        ContentUnavailableView("No pending request",systemImage:"checkmark.circle",description:Text("It may have been answered on your Mac."))
                    }
                    if let error = model.agentRequestError { Text(error).font(.subheadline).foregroundStyle(.red) }
                }.padding(24)
            }
            .background(Color(uiColor:.systemGroupedBackground))
            .navigationTitle(model.agentRequestProvider?.title ?? "Codex").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Close") { model.closeAgentRequests() } }
                ToolbarItem(placement:.topBarTrailing) { Button { model.refreshAgentRequests(clearError: true) } label: { Image(systemName:"arrow.clockwise") }.accessibilityLabel("Refresh request").disabled(model.agentReplyBusy || model.agentRequestLoading) }
            }
            .interactiveDismissDisabled(model.agentReplyBusy)
            .onChange(of: request?.id) { _, _ in answers = [:]; customQuestions = []; focusedQuestion = nil }
            .task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for:.seconds(2)) } catch { return }
                    if !model.agentReplyBusy && !model.agentRequestLoading { model.refreshAgentRequests() }
                }
            }
        }
    }
    private func answer(_ id:String) -> Binding<String> {
        Binding(get:{answers[id] ?? ""},set:{answers[id] = String($0.prefix(2000))})
    }
}
