el_cl_genesis_data_generator = import_module(
    "github.com/ethpandaops/ethereum-package/src/prelaunch_data_generator/el_cl_genesis/el_cl_genesis_generator.star",
)

execution = import_module("./src/nodes/execution/execution.star")
service_module = import_module("./src/services/service.star")
beacond = import_module("./src/nodes/consensus/beacond/launcher.star")
networks = import_module("./src/networks/networks.star")
port_spec_lib = import_module("./src/lib/port_spec.star")
nodes = import_module("./src/nodes/nodes.star")
nginx = import_module("./src/services/nginx/nginx.star")
constants = import_module("./src/constants.star")
spamoor = import_module("./src/services/spamoor/launcher.star")
prometheus = import_module("./src/observability/prometheus/prometheus.star")
grafana = import_module("./src/observability/grafana/grafana.star")
pyroscope = import_module("./src/observability/pyroscope/pyroscope.star")
tx_fuzz = import_module("./src/services/tx_fuzz/launcher.star")
blutgang = import_module("./src/services/blutgang/launcher.star")
blockscout = import_module("./src/services/blockscout/launcher.star")

def run(plan, network_configuration = {}, node_settings = {}, eth_json_rpc_endpoints = [], additional_services = [], metrics_enabled_services = []):
    """
    Initiates the execution plan with the specified number of validators and arguments.

    Args:
    plan: The execution plan to be run.
    args: Additional arguments to configure the plan. Defaults to an empty dictionary.
    """

    # all_node_types = [validators["type"], full_nodes["type"], seed_nodes["type"]]
    # all_node_settings = nodes.parse_node_settings(node_settings, all_node_types)

    # Get chain configuration from network_configuration, if not provided, use default values
    chain_id = network_configuration.get("chain_id", 80087)
    chain_spec = network_configuration.get("chain_spec", "devnet")

    plan.print("CHAIN_ID: {}".format(chain_id), "CHAIN_SPEC: {}".format(chain_spec))

    next_free_prefunded_account = 0
    validators = nodes.parse_nodes_from_dict(network_configuration["validators"], node_settings)
    full_nodes = nodes.parse_nodes_from_dict(network_configuration["full_nodes"], node_settings)
    seed_nodes = nodes.parse_nodes_from_dict(network_configuration["seed_nodes"], node_settings)
    num_validators = len(validators)

    # 1. Initialize EVM genesis data
    evm_genesis_data = networks.get_genesis_data(plan)

    all_nodes = []
    all_nodes.extend(validators)
    all_nodes.extend(seed_nodes)
    all_nodes.extend(full_nodes)
    node_modules = {}
    for node in all_nodes:
        if node.el_type not in node_modules.keys():
            node_path = "./src/nodes/execution/{}/config.star".format(node.el_type)
            node_module = import_module(node_path)
            node_modules[node.el_type] = node_module

    # 2. Upload files
    jwt_file, kzg_trusted_setup = execution.upload_global_files(plan, node_modules, chain_id)

    # 3. Perform genesis ceremony for the CL genesis deposits.
    stored_configs = beacond.perform_genesis_deposits_ceremony(plan, validators, jwt_file, chain_id, chain_spec)

    # 4 a. Create genesis files only once and pass it to the node configs
    genesis_files = nodes.create_genesis_files_part1(plan, chain_id)

    # 4b. Modify the eth genesis file with the premined deposits && finalize CL genesis file.
    # Get the deposit storage values stored in env variables
    env_vars = beacond.modify_genesis_files_deposits(plan, validators, genesis_files, chain_id, chain_spec, stored_configs)

    # Extract values from env_vars
    genesis_deposits_root = env_vars.get("GENESIS_DEPOSITS_ROOT")
    genesis_deposit_count_hex = env_vars.get("GENESIS_DEPOSIT_COUNT_HEX")

    # 4c. Modify the eth genesis files with the ENV VARS
    genesis_files = nodes.create_genesis_files_part2(plan, chain_id, genesis_deposits_root, genesis_deposit_count_hex)

    el_enode_addrs = []
    metrics_enabled_services = metrics_enabled_services[:]

    consensus_node_peering_info = []
    all_consensus_peering_info = {}

    # Execute only if geth is present
    # This is needed as we have a geth config file which needs to be templated
    geth_config_artifact = None
    if "geth" in node_modules and node_modules["geth"] != None:
        geth_config_artifact = node_modules["geth"].process_geth_config(plan, chain_id)

    # Start seed nodes
    seed_node_el_client_configs = []
    for n, seed in enumerate(seed_nodes):
        el_client_config = execution.generate_node_config(plan, node_modules, seed, chain_id, chain_spec, genesis_files, geth_config_artifact)
        seed_node_el_client_configs.append(el_client_config)
    if seed_node_el_client_configs != []:
        seed_node_el_clients = execution.deploy_nodes(plan, seed_node_el_client_configs)
    for n, seed in enumerate(seed_nodes):
        enode_addr = execution.get_enode_addr(plan, seed.el_service_name)
        el_enode_addrs.append(enode_addr)
        metrics_enabled_services = execution.add_metrics(metrics_enabled_services, seed, seed.el_service_name, seed_node_el_clients[seed.el_service_name], node_modules)
    seed_node_configs = {}
    for n, seed in enumerate(seed_nodes):
        seed_node_config = beacond.create_node_config(plan, seed, consensus_node_peering_info, seed.el_service_name, chain_id, chain_spec, genesis_deposits_root, genesis_deposit_count_hex, jwt_file, kzg_trusted_setup)
        seed_node_configs[seed.cl_service_name] = seed_node_config
    seed_nodes_clients = plan.add_services(
        configs = seed_node_configs,
    )
    for n, seed_client in enumerate(seed_nodes):
        peer_info = beacond.get_peer_info(plan, seed_client.cl_service_name)
        consensus_node_peering_info.append(peer_info)
        metrics_enabled_services.append({
            "name": seed_client.cl_service_name,
            "service": seed_nodes_clients[seed_client.cl_service_name],
            "metrics_path": beacond.METRICS_PATH,
        })

    # 5. Start full nodes (rpcs)
    full_node_configs = {}
    full_node_el_client_configs = []
    full_node_el_clients = {}

    for n, full in enumerate(full_nodes):
        el_client_config = execution.generate_node_config(plan, node_modules, full, chain_id, chain_spec, genesis_files, geth_config_artifact, el_enode_addrs)
        full_node_el_client_configs.append(el_client_config)

    if full_node_el_client_configs != []:
        full_node_el_clients = execution.deploy_nodes(plan, full_node_el_client_configs, True)

    for n, full in enumerate(full_nodes):
        metrics_enabled_services = execution.add_metrics(metrics_enabled_services, full, full.el_service_name, full_node_el_clients[full.el_service_name], node_modules)

    for n, full in enumerate(full_nodes):
        # 5b. Launch CL
        full_node_config = beacond.create_node_config(plan, full, consensus_node_peering_info, full.el_service_name, chain_id, chain_spec, genesis_deposits_root, genesis_deposit_count_hex, jwt_file, kzg_trusted_setup)
        full_node_configs[full.cl_service_name] = full_node_config

    if full_node_configs != {}:
        services = plan.add_services(
            configs = full_node_configs,
        )
    for n, full_node in enumerate(full_nodes):
        peer_info = beacond.get_peer_info(plan, full_node.cl_service_name)
        all_consensus_peering_info[full_node.cl_service_name] = peer_info
        metrics_enabled_services.append({
            "name": full_node.cl_service_name,
            "service": services[full_node.cl_service_name],
            "metrics_path": beacond.METRICS_PATH,
        })

    # 4. Start network validators
    validator_node_el_clients = []

    for n, validator in enumerate(validators):
        el_client_config = execution.generate_node_config(plan, node_modules, validator, chain_id, chain_spec, genesis_files, geth_config_artifact, el_enode_addrs)
        validator_node_el_clients.append(el_client_config)

    validator_el_clients = execution.deploy_nodes(plan, validator_node_el_clients)

    for n, validator in enumerate(validators):
        metrics_enabled_services = execution.add_metrics(metrics_enabled_services, validator, validator.el_service_name, validator_el_clients[validator.el_service_name], node_modules)

    validator_node_configs = {}
    for n, validator in enumerate(validators):
        validator_node_config = beacond.create_node_config(plan, validator, consensus_node_peering_info, validator.el_service_name, chain_id, chain_spec, genesis_deposits_root, genesis_deposit_count_hex, jwt_file, kzg_trusted_setup)
        validator_node_configs[validator.cl_service_name] = validator_node_config

    cl_clients = plan.add_services(
        configs = validator_node_configs,
    )

    for n, validator in enumerate(validators):
        peer_info = beacond.get_peer_info(plan, validator.cl_service_name)
        all_consensus_peering_info[validator.cl_service_name] = peer_info
        metrics_enabled_services.append({
            "name": validator.cl_service_name,
            "service": cl_clients[validator.cl_service_name],
            "metrics_path": beacond.METRICS_PATH,
        })

    for n, seed_node in enumerate(seed_nodes):
        beacond.dial_unsafe_peers(plan, seed_node.cl_service_name, all_consensus_peering_info)

    # Get only the first rpc endpoint
    eth_json_rpc_endpoint = eth_json_rpc_endpoints[0]
    endpoint_type = eth_json_rpc_endpoint["type"]
    plan.print("RPC Endpoint Type:", endpoint_type)
    if endpoint_type == "nginx":
        plan.print("Launching RPCs for ", endpoint_type)
        nginx.get_config(plan, eth_json_rpc_endpoint["clients"])

    elif endpoint_type == "blutgang":
        plan.print("Launching blutgang")
        blutgang_config_template = read_file(
            constants.BLUTGANG_CONFIG_TEMPLATE_FILEPATH,
        )
        blutgang.launch_blutgang(
            plan,
            blutgang_config_template,
            full_node_el_clients,
            eth_json_rpc_endpoint["clients"],
            "kurtosis",
        )

    else:
        plan.print("Invalid type for eth_json_rpc_endpoint")

    # 7. Start additional services
    prometheus_url = ""
    for s_dict in additional_services:
        s = service_module.parse_service_from_dict(s_dict)
        if s.name == "spamoor":
            plan.print("Launching spamoor")
            ip_spamoor = plan.get_service(endpoint_type).ip_address
            port_spamoor = plan.get_service(endpoint_type).ports["http"].number
            spamoor.launch_spamoor(
                plan,
                constants.PRE_FUNDED_ACCOUNTS[next_free_prefunded_account],
                "http://{}:{}".format(ip_spamoor, port_spamoor),
            )
            next_free_prefunded_account += 1
            plan.print("Successfully launched spamoor")
        elif s.name == "tx-fuzz":
            plan.print("Launching tx-fuzz")
            if "replicas" not in s_dict:
                s.replicas = 1
            next_free_prefunded_account = tx_fuzz.launch_tx_fuzzes(plan, s.replicas, next_free_prefunded_account, full_node_el_client_configs, full_node_el_clients, [])
            # next_free_prefunded_account = tx_fuzz.launch_tx_fuzzes_gang(plan, s.replicas, next_free_prefunded_account, [])

        elif s.name == "prometheus":
            prometheus_url = prometheus.start(plan, metrics_enabled_services)
        elif s.name == "grafana":
            grafana.start(plan, prometheus_url)
        elif s.name == "pyroscope":
            pyroscope.run(plan)
        elif s.name == "blockscout":
            plan.print("Launching blockscout")
            blockscout.launch_blockscout(
                plan,
                full_node_el_clients,
                s.client,
                False,
            )
    plan.print("Successfully launched development network")
