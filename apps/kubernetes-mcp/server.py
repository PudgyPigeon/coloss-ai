from flask import Flask, jsonify, request
from kubernetes import config, client
import os

app = Flask(__name__)

# Load Kubernetes configuration
v1 = None
apps_v1 = None
try:
    config.load_kube_config()
    v1 = client.CoreV1Api()
    apps_v1 = client.AppsV1Api()
except config.ConfigException:
    print("Could not load Kubernetes config from default location. Trying in-cluster config.")
    try:
        config.load_incluster_config()
        v1 = client.CoreV1Api()
        apps_v1 = client.AppsV1Api()
    except config.ConfigException as e:
        print(f"Could not load in-cluster Kubernetes config: {e}")
        print("Kubernetes client not initialized. API endpoints will not function.")

def get_kubernetes_clients():
    """Helper to return initialized Kubernetes API clients."""
    return v1, apps_v1

@app.route('/kubernetes/resources', methods=['GET'])
def list_kubernetes_resources():
    """
    Lists various Kubernetes resources (pods, deployments, services, namespaces).
    Query parameters:
        namespace (str): Specific namespace to query. Use 'all' for all namespaces. (default: 'all')
        type (str): Type of resource to list (e.g., 'pods', 'deployments', 'services', 'namespaces', or 'all'). (default: 'all')
    """
    core_v1_api, apps_v1_api = get_kubernetes_clients()
    if core_v1_api is None:
        return jsonify({"error": "Kubernetes client not initialized. Check server logs."}), 500

    namespace = request.args.get('namespace', default='all')
    resource_type = request.args.get('type', default='all').lower()

    resources = {}
    try:
        if resource_type in ['all', 'pods']:
            if namespace == 'all':
                pods = core_v1_api.list_pod_for_all_namespaces().items
            else:
                pods = core_v1_api.list_namespaced_pod(namespace=namespace).items
            resources['pods'] = [{"name": p.metadata.name, "namespace": p.metadata.namespace, "status": p.status.phase} for p in pods]

        if resource_type in ['all', 'deployments']:
            if apps_v1_api: # Ensure apps_v1_api is initialized
                if namespace == 'all':
                    deployments = apps_v1_api.list_deployment_for_all_namespaces().items
                else:
                    deployments = apps_v1_api.list_namespaced_deployment(namespace=namespace).items
                resources['deployments'] = [{"name": d.metadata.name, "namespace": d.metadata.namespace, "replicas": d.spec.replicas, "available_replicas": d.status.available_replicas if d.status.available_replicas else 0} for d in deployments]
            else:
                resources['deployments'] = "AppsV1Api not initialized."

        if resource_type in ['all', 'services']:
            if namespace == 'all':
                services = core_v1_api.list_service_for_all_namespaces().items
            else:
                services = core_v1_api.list_namespaced_service(namespace=namespace).items
            resources['services'] = [{"name": s.metadata.name, "namespace": s.metadata.namespace, "cluster_ip": s.spec.cluster_ip, "ports": [{"name": p.name, "port": p.port, "protocol": p.protocol} for p in s.spec.ports] if s.spec.ports else []} for s in services]

        if resource_type in ['all', 'namespaces']:
            # Namespaces are global, so 'all' is the only relevant scope for listing them
            namespaces = core_v1_api.list_namespace().items
            resources['namespaces'] = [{"name": ns.metadata.name, "status": ns.status.phase} for ns in namespaces]

        return jsonify(resources)
    except client.ApiException as e:
        return jsonify({"error": f"Kubernetes API error: {e.reason}", "status": e.status, "details": e.body}), e.status
    except Exception as e:
        return jsonify({"error": f"An unexpected error occurred: {str(e)}"}), 500

@app.route('/kubernetes/logs/<namespace>/<pod_name>', methods=['GET'])
def get_pod_logs(namespace, pod_name):
    """
    Fetches logs for a specific pod in a given namespace.
    Path parameters:
        namespace (str): The namespace of the pod.
        pod_name (str): The name of the pod.
    """
    core_v1_api, _ = get_kubernetes_clients()
    if core_v1_api is None:
        return jsonify({"error": "Kubernetes client not initialized. Check server logs."}), 500

    try:
        logs = core_v1_api.read_namespaced_pod_log(name=pod_name, namespace=namespace)
        return jsonify({"pod": pod_name, "namespace": namespace, "logs": logs})
    except client.ApiException as e:
        if e.status == 404:
            return jsonify({"error": f"Pod '{pod_name}' not found in namespace '{namespace}'"}), 404
        return jsonify({"error": f"Kubernetes API error: {e.reason}", "status": e.status, "details": e.body}), e.status
    except Exception as e:
        return jsonify({"error": f"An unexpected error occurred: {str(e)}"}), 500

@app.route('/healthz', methods=['GET'])
def health_check():
    return jsonify({"status": "ok", "message": "Kubernetes MCP server is running."})

if __name__ == '__main__':
    port = int(os.environ.get('KUBERNETES_MCP_PORT', 30091))
    app.run(host='0.0.0.0', port=port)
