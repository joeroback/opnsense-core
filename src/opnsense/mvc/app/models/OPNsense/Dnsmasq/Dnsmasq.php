<?php

/*
 * Copyright (C) 2025 Deciso B.V.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 * OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

namespace OPNsense\Dnsmasq;

use OPNsense\Base\BaseModel;
use OPNsense\Base\Messages\Message;
use OPNsense\Core\Backend;

/**
 * Class Dnsmasq
 * @package OPNsense\Dnsmasq
 */
class Dnsmasq extends BaseModel
{
    /**
     * {@inheritdoc}
     */
    protected function init()
    {
        $this->dns_port = strlen($this->port) ? (string)$this->port : '53'; /* port defaults */
    }

    /**
     * {@inheritdoc}
     */
    public function performValidation($validateFullModel = false)
    {
        $this->dns_port = strlen($this->port) ? (string)$this->port : '53'; /* port defaults */

        $messages = parent::performValidation($validateFullModel);

        if (
            ($validateFullModel || $this->enable->isFieldChanged() || $this->port->isFieldChanged()) &&
            !empty((string)$this->enable)
        ) {
            foreach (json_decode((new Backend())->configdpRun('service list'), true) as $service) {
                if (empty($service['dns_ports'])) {
                    continue;
                }
                if (!is_array($service['dns_ports'])) {
                    syslog(LOG_ERR, sprintf('Service %s (%s) reported a faulty "dns_ports" entry.', $service['description'], $service['name']));
                    continue;
                }
                if ($service['name'] != 'dnsmasq' && in_array((string)$this->dns_port, $service['dns_ports'])) {
                    $messages->appendMessage(new Message(
                        sprintf(gettext('%s is currently using this port.'), $service['description']),
                        $this->port->getInternalXMLTagName()
                    ));
                    break;
                }
            }
        }

        return $messages;
    }
}
