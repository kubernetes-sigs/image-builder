# This file is part of cloud-init. See LICENSE file for license information.

import logging
import os

from cloudinit import handlers, helpers, sources, util
from cloudinit.handlers.boot_hook import BootHookPartHandler
from cloudinit.handlers.jinja_template import JinjaTemplatePartHandler
from cloudinit.handlers.cloud_config import CloudConfigPartHandler
from cloudinit.handlers.shell_script import ShellScriptPartHandler
from cloudinit.settings import PER_ALWAYS
from cloudinit.sources import DataSourceEc2
from cloudinit.handlers.jinja_template import (
    render_jinja_payload_from_file,
)

LOG = logging.getLogger(__name__)


class BootHookPartHandlerModified(BootHookPartHandler):
    def __init__(self, paths, datasource, **_kwargs):
        super().__init__(paths, datasource)
        self.output = None

    def handle_part(self, data, ctype, filename, payload, frequency):
        """Save the output of the script"""
        if ctype in handlers.CONTENT_SIGNALS:
            return

        # modify the payload to not restart cloud-init
        # TODO: work with upstream to remove this restart
        restart_index = payload.find("systemctl restart cloud-init")
        if -1 != restart_index:
            LOG.warning(
                "Kubernetes is trying to restart cloud-init. This is no "
                "longer necessary and is temporarily circumvented by "
                "cloud-init. This will be a hard error in the future."
            )
        payload = payload[:restart_index] + "#" + payload[restart_index:]
        super().handle_part(data, ctype, filename, payload, frequency)


class DataSourceEc2Kubernetes(DataSourceEc2.DataSourceEc2):
    def _get_data(self):
        super()._get_data()

        # Get initial user-data
        user_data_msg = self.get_userdata(True)
        LOG.info("User-data received:[\n%s]", user_data_msg)
        self.persist_instance_data()

        # This is required to get path of the instance
        self.paths.datasource = self

        # Boilerplate handler setup
        c_handlers = helpers.ContentHandlers()
        cloudconfig_handler = CloudConfigPartHandler(self.paths)
        shellscript_handler = ShellScriptPartHandler(self.paths)
        boothook_handler = BootHookPartHandlerModified(self.paths, self)
        jinja_handler = JinjaTemplatePartHandler(
            self.paths,
            sub_handlers=[
                cloudconfig_handler,
                shellscript_handler,
                boothook_handler,
            ],
        )
        c_handlers.register(boothook_handler, overwrite=False)
        c_handlers.register(jinja_handler, overwrite=False)
        LOG.debug("Registered handlers %s and %s", boothook_handler, jinja_handler)

        # Walk the user data MIME
        handlers.walk(
            user_data_msg,
            handlers.walker_callback,
            data={
                "handlers": c_handlers,
                "handlerdir": self.paths.get_ipath("handlers"),
                "data": None,
                "frequency": PER_ALWAYS,
                "handlercount": 0,
                "excluded": [],
            },
        )
        LOG.info("User-data before update:[\n%s]", self.userdata_raw)
        secret_userdata = "/etc/secret-userdata.txt"
        # Get the boothook output, save it as user-data
        # TODO: work with upstream to put this somewhere more sensible like:
        # /var/lib/cloud/instances/{{v1.instance_id}}/ec2-kubernetes-userdata.txt
        userdata_raw = util.load_text_file(secret_userdata)
        LOG.info("Secret user-data:[\n%s]", self.userdata_raw)

        uid = os.getuid()
        redacted_data_fn = self.paths.get_runpath("instance_data")
        if uid == 0:
            instance_data_fn = self.paths.get_runpath("instance_data_sensitive")
            if not os.path.exists(instance_data_fn):
                LOG.warning(
                    "Missing root-readable %s. Using redacted %s instead.",
                    instance_data_fn,
                    redacted_data_fn,
                )
                instance_data_fn = redacted_data_fn
        else:
            instance_data_fn = redacted_data_fn
        rendered_payload = render_jinja_payload_from_file(
            payload=userdata_raw,
            payload_fn=secret_userdata,
            instance_data_file=instance_data_fn,
        )
        util.write_file(
            "/etc/cloud/cloud.cfg.d/99_kubeadm_bootstrap.cfg", rendered_payload
        )
        self.userdata_raw = rendered_payload
        return True


class DataSourceEc2KubernetesLocal(DataSourceEc2Kubernetes):
    def _get_data(self):
        return super(DataSourceEc2KubernetesLocal, self).get_data()


# Used to match classes to dependencies
datasources = [
    (
        DataSourceEc2KubernetesLocal,
        (sources.DEP_FILESYSTEM,),
    ),
    (DataSourceEc2Kubernetes, (sources.DEP_FILESYSTEM, sources.DEP_NETWORK)),
]


# Return a list of data sources that match this set of dependencies
def get_datasource_list(depends):
    return sources.list_from_depends(depends, datasources)
