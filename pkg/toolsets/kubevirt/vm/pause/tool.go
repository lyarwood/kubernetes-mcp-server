package pause

import (
	"fmt"

	"github.com/containers/kubernetes-mcp-server/pkg/api"
	"github.com/google/jsonschema-go/jsonschema"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/runtime/serializer"
	"k8s.io/client-go/rest"
	"k8s.io/utils/ptr"
)

var (
	// SchemeGroupVersion is the group version used for KubeVirt subresources
	SchemeGroupVersion = schema.GroupVersion{Group: "subresources.kubevirt.io", Version: "v1"}

	// Scheme is the runtime scheme for KubeVirt subresources
	Scheme = runtime.NewScheme()

	// Codecs provides access to encoding and decoding for the scheme
	Codecs = serializer.NewCodecFactory(Scheme)
)

func Tools() []api.ServerTool {
	return []api.ServerTool{
		{
			Tool: api.Tool{
				Name:        "vm_pause",
				Description: "Pause a running VirtualMachine by pausing its associated VirtualMachineInstance using the KubeVirt pause subresource API",
				InputSchema: &jsonschema.Schema{
					Type: "object",
					Properties: map[string]*jsonschema.Schema{
						"namespace": {
							Type:        "string",
							Description: "The namespace of the virtual machine",
						},
						"name": {
							Type:        "string",
							Description: "The name of the virtual machine to pause",
						},
					},
					Required: []string{"namespace", "name"},
				},
				Annotations: api.ToolAnnotations{
					Title:           "Virtual Machine: Pause",
					ReadOnlyHint:    ptr.To(false),
					DestructiveHint: ptr.To(false),
					IdempotentHint:  ptr.To(true),
					OpenWorldHint:   ptr.To(false),
				},
			},
			Handler: pause,
		},
	}
}

func pause(params api.ToolHandlerParams) (*api.ToolCallResult, error) {
	// Parse required parameters
	namespace, err := params.GetRequiredString("namespace")
	if err != nil {
		return api.NewToolCallResult("", err), nil
	}

	name, err := params.GetRequiredString("name")
	if err != nil {
		return api.NewToolCallResult("", err), nil
	}

	// Get REST config
	restConfig := params.RESTConfig()
	if restConfig == nil {
		return api.NewToolCallResult("", fmt.Errorf("failed to get REST config")), nil
	}

	// Create a REST client for the KubeVirt subresource API
	restConfig.GroupVersion = &SchemeGroupVersion
	restConfig.APIPath = "/apis"
	restConfig.NegotiatedSerializer = Codecs.WithoutConversion()

	restClient, err := rest.RESTClientFor(restConfig)
	if err != nil {
		return api.NewToolCallResult("", fmt.Errorf("failed to create REST client: %w", err)), nil
	}

	// Call the pause subresource on the VMI
	// PUT /apis/subresources.kubevirt.io/v1/namespaces/{namespace}/virtualmachineinstances/{name}/pause
	result := restClient.Put().
		Namespace(namespace).
		Resource("virtualmachineinstances").
		Name(name).
		SubResource("pause").
		Do(params.Context)

	if err := result.Error(); err != nil {
		return api.NewToolCallResult("", fmt.Errorf("failed to pause VirtualMachineInstance: %w", err)), nil
	}

	return api.NewToolCallResult(fmt.Sprintf("VirtualMachineInstance %s/%s paused successfully", namespace, name), nil), nil
}
