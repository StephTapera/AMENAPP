// HelixViewModel.swift
// AMENAPP
//
// ObservableObject view model for the Helix workspace automation system.

import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

@MainActor
class HelixViewModel: ObservableObject {

    @Published var nodes: [HelixNode] = []
    @Published var workflows: [HelixWorkflow] = []
    @Published var workflowRuns: [HelixWorkflowRun] = []
    @Published var isLoading = false

    private lazy var db = Firestore.firestore()
    private var nodesListener: ListenerRegistration?
    private var workflowsListener: ListenerRegistration?

    // MARK: - Load Nodes

    func loadNodes(workspaceId: String) {
        nodesListener?.remove()
        dlog("HelixViewModel: loading nodes for workspace \(workspaceId)")
        nodesListener = db.collection("helixNodes")
            .whereField("workspaceId", isEqualTo: workspaceId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    dlog("HelixViewModel: nodes listener error — \(error.localizedDescription)")
                    return
                }
                self.nodes = (snapshot?.documents ?? []).compactMap {
                    try? $0.data(as: HelixNode.self)
                }
                dlog("HelixViewModel: loaded \(self.nodes.count) nodes")
            }
    }

    // MARK: - Load Workflows

    func loadWorkflows(workspaceId: String) {
        workflowsListener?.remove()
        dlog("HelixViewModel: loading workflows for workspace \(workspaceId)")
        workflowsListener = db.collection("helixWorkflows")
            .whereField("workspaceId", isEqualTo: workspaceId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    dlog("HelixViewModel: workflows listener error — \(error.localizedDescription)")
                    return
                }
                self.workflows = (snapshot?.documents ?? []).compactMap {
                    try? $0.data(as: HelixWorkflow.self)
                }
                dlog("HelixViewModel: loaded \(self.workflows.count) workflows")
            }
    }

    // MARK: - Load Workflow Runs

    func loadWorkflowRuns(workflowId: String) async -> [HelixWorkflowRun] {
        dlog("HelixViewModel: loading runs for workflow \(workflowId)")
        do {
            let snapshot = try await db.collection("helixWorkflowRuns")
                .whereField("workflowId", isEqualTo: workflowId)
                .order(by: "startedAt", descending: true)
                .limit(to: 10)
                .getDocuments()
            let runs = snapshot.documents.compactMap { try? $0.data(as: HelixWorkflowRun.self) }
            dlog("HelixViewModel: loaded \(runs.count) runs")
            return runs
        } catch {
            dlog("HelixViewModel: loadWorkflowRuns error — \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Create Node

    func createNode(_ node: HelixNode) async throws {
        dlog("HelixViewModel: creating node '\(node.label)'")
        try db.collection("helixNodes").addDocument(from: node)
    }

    // MARK: - Create Workflow

    func createWorkflow(_ workflow: HelixWorkflow) async throws {
        dlog("HelixViewModel: creating workflow '\(workflow.name)'")
        try db.collection("helixWorkflows").addDocument(from: workflow)
    }

    // MARK: - Create From Template

    func createFromTemplate(_ template: WorkflowTemplate, workspaceId: String) async throws -> HelixWorkflow {
        let uid = Auth.auth().currentUser?.uid ?? "unknown"
        let workflow = HelixWorkflow(
            workspaceId: workspaceId,
            name: template.name,
            description: template.description,
            triggerType: template.triggerType,
            steps: template.steps,
            isActive: true,
            createdBy: uid
        )
        try db.collection("helixWorkflows").addDocument(from: workflow)
        dlog("HelixViewModel: created workflow from template '\(template.name)'")
        return workflow
    }

    // MARK: - Toggle Workflow

    func toggleWorkflow(_ workflow: HelixWorkflow) async throws {
        guard let id = workflow.id else { return }
        let newState = !workflow.isActive
        dlog("HelixViewModel: toggling workflow \(id) → active=\(newState)")
        try await db.collection("helixWorkflows").document(id).updateData([
            "isActive": newState
        ])
    }

    // MARK: - Delete Workflow

    func deleteWorkflow(_ workflow: HelixWorkflow) async throws {
        guard let id = workflow.id else { return }
        dlog("HelixViewModel: deleting workflow \(id)")
        try await db.collection("helixWorkflows").document(id).delete()
    }

    // MARK: - Edges

    func edges() -> [HelixEdge] {
        var result: [HelixEdge] = []
        for node in nodes {
            guard let sourceId = node.id else { continue }
            for targetId in node.connectedNodeIds {
                result.append(HelixEdge(sourceId: sourceId, targetId: targetId))
            }
        }
        return result
    }

    // MARK: - Deinit

    deinit {
        nodesListener?.remove()
        workflowsListener?.remove()
    }
}
