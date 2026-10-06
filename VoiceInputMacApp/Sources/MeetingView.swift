import SwiftUI

/// 音频源类型
enum AudioSourceType: String, CaseIterable, Identifiable {
    case microphone = "麦克风"
    case system = "系统音频"
    case mixed = "混合"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .microphone: return "mic.fill"
        case .system: return "speaker.wave.2.fill"
        case .mixed: return "waveform.circle"
        }
    }
    
    var description: String {
        switch self {
        case .microphone: return "面对面会议"
        case .system: return "线上会议（Zoom/Teams）"
        case .mixed: return "同时录制"
        }
    }
}

struct MeetingView: View {
    @ObservedObject private var manager = MeetingManager.shared
    @State private var selectedMeeting: UUID?
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var isBusy = false  // 防止重复点击
    @State private var audioSourceType: AudioSourceType = .microphone  // 音频源选择
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧列表
            meetingList
                .frame(width: 200)
            
            Divider()
            
            // 右侧详情
            if let id = selectedMeeting, manager.meetings.contains(where: { $0.id == id }) {
                MeetingDetailView(meeting: binding(for: id))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("选择一条会议记录查看详情")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private var meetingList: some View {
        VStack(spacing: 0) {
            // 顶部操作栏
            VStack(spacing: 8) {
                HStack {
                    Text("会议")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    
                    if manager.isRecording {
                        // 录音中 → 停止按钮
                        Button(action: stopRecording) {
                            Label(String(format: "%.0fs", recordingDuration), systemImage: "stop.circle.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        // 开始录音按钮
                        Button(action: startRecording) {
                            HStack(spacing: 4) {
                                Image(systemName: audioSourceType.icon)
                                    .font(.system(size: 12))
                                Text("开始录音")
                                    .font(.system(size: 11))
                            }
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // 音频源选择（仅在不录音时显示）
                if !manager.isRecording {
                    Picker("音频源", selection: $audioSourceType) {
                        ForEach(AudioSourceType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .font(.system(size: 10))
                    
                    Text(audioSourceType.description)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            
            Divider()
            
            // 会议列表
            if manager.meetings.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "waveform.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("暂无会议记录")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Text("点击右上角麦克风开始录音")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(manager.meetings) { meeting in
                            MeetingRow(meeting: meeting, isSelected: selectedMeeting == meeting.id) {
                                selectedMeeting = meeting.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Divider()
            
            // 底部操作
            HStack {
                if !manager.meetings.isEmpty {
                    Button("清空全部") {
                        manager.deleteAll()
                        selectedMeeting = nil
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.bordered)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(manager.meetings.count) 条记录")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
        }
    }
    
    private func startRecording() {
        guard !isBusy, !manager.isRecording else { return }
        isBusy = true
        
        let id = manager.startMeetingRecording(audioSourceType: audioSourceType)
        selectedMeeting = id
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingDuration += 0.1
        }
        
        isBusy = false
    }
    
    private func stopRecording() {
        guard !isBusy, manager.isRecording else { return }
        isBusy = true
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // 停止录音（Apple Speech 直接转录，无需 AudioRecorder）
        manager.stopMeetingRecording(duration: recordingDuration)
        
        isBusy = false
    }
    
    private func binding(for id: UUID) -> Binding<Meeting> {
        Binding(
            get: { manager.meetings.first(where: { $0.id == id }) ?? Meeting() },
            set: { newMeeting in
                if let idx = manager.meetings.firstIndex(where: { $0.id == id }) {
                    manager.meetings[idx] = newMeeting
                    manager.saveMeetings()
                }
            }
        )
    }
}

// MARK: - Meeting Row

struct MeetingRow: View {
    let meeting: Meeting
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(meeting.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    if meeting.isProcessing {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    }
                }
                
                HStack(spacing: 6) {
                    Text(dateString(meeting.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    
                    if meeting.duration > 0 {
                        Text(durationString(meeting.duration))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    
                    if !meeting.summary.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    private func dateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d HH:mm"
        return fmt.string(from: date)
    }
    
    private func durationString(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return mins > 0 ? "\(mins)分\(secs)秒" : "\(secs)秒"
    }
}

// MARK: - Meeting Detail View

struct MeetingDetailView: View {
    @Binding var meeting: Meeting
    @State private var showTranscription = false
    @State private var copiedField: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 标题
                HStack {
                    Text(meeting.title)
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    Button(role: .destructive) {
                        MeetingManager.shared.deleteMeeting(id: meeting.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                }
                
                // 元信息
                HStack(spacing: 16) {
                    Label(dateString(meeting.date), systemImage: "calendar")
                    if meeting.duration > 0 {
                        Label(durationString(meeting.duration), systemImage: "clock")
                    }
                    Label("\(meeting.transcription.count) 字", systemImage: "text.quote")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                
                Divider()
                
                // AI 总结
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("AI 会议纪要", systemImage: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        if !meeting.summary.isEmpty {
                            copyButton("summary", meeting.summary)
                        }
                        if meeting.transcription.isEmpty == false && meeting.summary.isEmpty {
                            Button("重新总结") {
                                MeetingManager.shared.summarizeMeeting(id: meeting.id)
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    if meeting.isProcessing && meeting.summary.isEmpty {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("正在处理中...")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else if !meeting.summary.isEmpty {
                        Text(meeting.summary)
                            .font(.system(size: 13))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
                    } else {
                        Text("等待转录完成后自动生成总结")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    }
                }
                
                // 转录原文
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(action: { showTranscription.toggle() }) {
                            Label("转录原文", systemImage: showTranscription ? "chevron.down" : "chevron.right")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        if showTranscription && !meeting.transcription.isEmpty {
                            copyButton("transcription", meeting.transcription)
                        }
                    }
                    
                    if showTranscription {
                        if meeting.isProcessing && meeting.transcription.isEmpty {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("正在转录中...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                        } else if !meeting.transcription.isEmpty {
                            Text(meeting.transcription)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineSpacing(2)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
                        }
                    }
                }
            }
            .padding(20)
        }
    }
    
    private func copyButton(_ field: String, _ text: String) -> some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copiedField = field
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copiedField = nil
            }
        }) {
            Image(systemName: copiedField == field ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
        }
        .buttonStyle(.bordered)
    }
    
    private func dateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy年M月d日 HH:mm"
        return fmt.string(from: date)
    }
    
    private func durationString(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return mins > 0 ? "\(mins)分\(secs)秒" : "\(secs)秒"
    }
}
